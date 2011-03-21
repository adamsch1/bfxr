package com.increpare.bfxr.synthesis.Mixer
{
	import com.increpare.bfxr.synthesis.IPlayerInterface;
	import com.increpare.bfxr.synthesis.ISerializable;
	import com.increpare.bfxr.synthesis.Synthesizer.SfxrSynth;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.SampleDataEvent;
	import flash.media.Sound;
	import flash.media.SoundChannel;
	import flash.utils.ByteArray;
	import flash.utils.Endian;

	public class MixerPlayer extends EventDispatcher implements ISerializable
	{
		public var id:int = -1;
		public var volume:Number = 1;
		public var tracks:Vector.<MixerTrackPlayer>;
		
		public function MixerPlayer() 
		{
			tracks = new Vector.<MixerTrackPlayer>();
			for (var i:int=0;i<MixerSynth.TRACK_COUNT;i++)
			{
				var mtp:MixerTrackPlayer = new MixerTrackPlayer();
				tracks.push(mtp);
			}		
			
			if (_zeros==null)
			{				
				_zeros = new ByteArray();
				for (i=0;i<400000;i++)
				{
					_zeros.writeFloat(0.0);
				}
			}
		}
				
		public function Serialize():String
		{
			var result:String="";
			result += id.toString() + ">";
			result += volume.toString() + ">";
			for (var i:int=0;i<tracks.length;i++)
			{
				if (i>0)
					result+=">";
				
				result += tracks[i].Serialize();
			}
			return result;
		}
		
		public function Deserialize(settings:String):void
		{
			var ar:Array = settings.split(">");
			id = int(ar[0]);
			volume = int(ar[1]);
			for (var i:int=2;i<ar.length;i++)
			{
				var s:String = ar[i];
				tracks[i-2].Deserialize(s);
			}
		}
				
		private var _updateCallback:Function=null;
		private var _lastplayeddata:String="";
		private var _caching:Boolean=false;
		private var _channel:SoundChannel;
		private var _sound:Sound;
		private var _waveData:ByteArray;
		private var _waveDataLength:int=-1;
		private var _waveDataBytes:int=-1;
		private var _waveDataPos:uint=0;
		private var _preparedsounds:Vector.<ByteArray>;
		private var _preparedvolumes:Vector.<Number>; //stores corresponding volumes
		private static var _zeros:ByteArray;
		
		public function play(updateCallback:Function=null):void
		{
			_updateCallback=updateCallback;
			
			var description:String = this.Serialize();
			if (_lastplayeddata!=description)
			{
				_lastplayeddata = description;
				
				//copy tracks over and add whitespace
				_preparedsounds = new Vector.<ByteArray>();
				_preparedvolumes = new Vector.<Number>();
				for (var i:int=0;i<tracks.length;i++)
				{
					if (tracks[i].IsSet()==false)
					{
						continue;
					}
					
					var b:ByteArray = new ByteArray();
										
					var silentbytes:int = int(tracks[i].data.onset*44100)*4;
					
					// create starting silence.
					while(silentbytes>0)
					{
						var bytestocopy:int=Math.min(silentbytes,_zeros.length);
						
						b.writeBytes(_zeros,0,bytestocopy);
						
						silentbytes-=bytestocopy;
					}
					
					b.writeBytes(tracks[i].synth.cachedWave);
					
					b.position=0;
					_preparedsounds.push(b);
					_preparedvolumes.push(tracks[i].data.volume);
				}
				
				Mix();
			}			
			
			if (_preparedsounds.length==0)
			{
				return;
			}
			
			if (_channel)
			{
				_channel.stop();
			}
			
			_waveData.position = 0;
			_waveDataLength = _waveData.length;
			_waveDataBytes = 24576;
			_waveDataPos = 0; 	
			_caching=true;
			if (!_sound) (_sound = new Sound()).addEventListener(SampleDataEvent.SAMPLE_DATA, onSoundData);
			
			_channel = _sound.play();
		}
		
		public function stop():void
		{
			if (_channel)
			{
				_channel.stop();
				_channel = null;
			}
		}
		
		/**
		 * Returns a ByteArray of the wave in the form of a .wav file, ready to be saved out
		 * @param	sampleRate		Sample rate to generate the .wav at	
		 * @param	bitDepth		Bit depth to generate the .wav at	
		 * @return					Wave in a .wav file
		 */
		public function getWavFile(sampleRate:uint = 44100, bitDepth:uint = 16):ByteArray
		{
			stop();			
			
			var waveDataBody : ByteArray = getWavByteArray(sampleRate,bitDepth);
			
			if (sampleRate != 44100) sampleRate = 22050;
			if (bitDepth != 16) bitDepth = 8;
			
			var soundLength:uint = waveDataBody.length;
			//if (bitDepth == 16) soundLength *= 2;
			//if (sampleRate == 22050) soundLength /= 2;
			
			var filesize:int = 36 + soundLength;
			var blockAlign:int = bitDepth / 8;
			var bytesPerSec:int = sampleRate * blockAlign;
			
			var wav:ByteArray = new ByteArray();
			
			// Header
			wav.endian = Endian.BIG_ENDIAN;
			wav.writeUnsignedInt(0x52494646);		// Chunk ID "RIFF"
			wav.endian = Endian.LITTLE_ENDIAN;
			wav.writeUnsignedInt(filesize);			// Chunck Data Size
			wav.endian = Endian.BIG_ENDIAN;
			wav.writeUnsignedInt(0x57415645);		// RIFF Type "WAVE"
			
			// Format Chunk
			wav.endian = Endian.BIG_ENDIAN;
			wav.writeUnsignedInt(0x666D7420);		// Chunk ID "fmt "
			wav.endian = Endian.LITTLE_ENDIAN;
			wav.writeUnsignedInt(16);				// Chunk Data Size
			wav.writeShort(1);						// Compression Code PCM
			wav.writeShort(1);						// Number of channels
			wav.writeUnsignedInt(sampleRate);		// Sample rate
			wav.writeUnsignedInt(bytesPerSec);		// Average bytes per second
			wav.writeShort(blockAlign);				// Block align
			wav.writeShort(bitDepth);				// Significant bits per sample
			
			// Data Chunk
			wav.endian = Endian.BIG_ENDIAN;
			wav.writeUnsignedInt(0x64617461);		// Chunk ID "data"
			wav.endian = Endian.LITTLE_ENDIAN;
			wav.writeUnsignedInt(soundLength);		// Chunk Data Size
			
			wav.writeBytes(waveDataBody);
			
			wav.position = 0;
			
			return wav;
		}
		
		private function getWavByteArray(sampleRate:uint = 44100, bitDepth:uint = 16):ByteArray
		{
			//synth all individual wave files
			var waves : Vector.<ByteArray> = new Vector.<ByteArray>();			
			
			_lastplayeddata=null;//so it'll regenerate them with proper data on next play, rather than playing back the wav file data.
			_preparedsounds = new Vector.<ByteArray>();
			_preparedvolumes = new Vector.<Number>();			
			for (var i:int=0;i<tracks.length;i++)
			{
				if (tracks[i].IsSet()==false)
				{
					continue;
				}
				
				var b:ByteArray = new ByteArray();
				
				var silentbytes:int= int(tracks[i].data.onset*44100);
				
				if (bitDepth==16)
					silentbytes*=2;
				if (sampleRate == 44100)
					silentbytes*=2;	
				
				// create starting silence.
				while(silentbytes>0)
				{
					var bytestocopy:int=Math.min(silentbytes,_zeros.length);
					
					b.writeBytes(_zeros,0,bytestocopy);
					
					silentbytes-=bytestocopy;
				}
				
				
				var synthwavefile:ByteArray = tracks[i].synth.getWavFile(sampleRate,bitDepth); 
				//assumes sourcesounds already populated by wav-compatible waves
				// 36 = skip past header info
				b.writeBytes(synthwavefile,36);				
				
				b.position=0;
				_preparedsounds.push(b);
				_preparedvolumes.push(tracks[i].data.volume);
			}
			
			//now to mix
			Mix(bitDepth==16 ? 2 : 1);
			
			
			return _waveData;
		}

		
		/** param is whether to work in bytes, shorts, or floats (1,2,4)*/
		private function Mix(unitsize:int=4):void
		{
			var trackcount:int=_preparedsounds.length;
			_waveData = new ByteArray();
						
			var added:Boolean=true;
			
			var i:int;
			
			switch(unitsize)
			{
				case 1:
					while (added)
					{
						added=false;
						var val:int=0;
						for (i=0;i<trackcount;i++)
						{
							if (_preparedsounds[i].position<_preparedsounds[i].length-unitsize)
							{
								val += _preparedsounds[i].readByte()*_preparedvolumes[i];
								added=true;
							}
						}
						
						val*=volume;
						
						if (val >= (1<<7))
							val=1<<7;
						if (val<= -(1<<7))
							val=-(1<<7);
						
						_waveData.writeByte(val);
					}
					break;
				case 2:
					while (added)
					{
						added=false;
						val=0;
						for (i=0;i<trackcount;i++)
						{
							if (_preparedsounds[i].position<_preparedsounds[i].length-unitsize)
							{
								val += _preparedsounds[i].readShort()*_preparedvolumes[i];
								added=true;
							}
						}
						
						val*=volume;						
						
						if (val >= (1<<15))
							val=1<<15;
						if (val<= -(1<<15))
							val=-(1<<15);
						
						_waveData.writeShort(val);
					}
					break;
				case 4:
					while (added)
					{
						added=false;
						var valf:Number=0;
						for (i=0;i<trackcount;i++)
						{
							if (_preparedsounds[i].position<_preparedsounds[i].length-unitsize)
							{
								valf += _preparedsounds[i].readFloat()*_preparedvolumes[i];
								added=true;
							}
						}
						
						valf*=volume;
						
						_waveData.writeFloat(valf);
					}
					break;
			}
		}
						
		private function onSoundData(e:SampleDataEvent) : void
		{		
			if (_updateCallback!=null)
			{
				_updateCallback(_waveDataPos/(4*44100));
			}
			
			if (_caching)
			{
				if(_waveDataPos + _waveDataBytes > _waveDataLength)
				{
					_waveDataBytes = _waveDataLength - _waveDataPos;
					dispatchEvent(new Event(SfxrSynth.PLAY_COMPLETE));	
				}
				
				if(_waveDataBytes > 0) e.data.writeBytes(_waveData, _waveDataPos, _waveDataBytes);
				
				//if too short..append data
				if (e.data.length<_waveDataBytes) 
				{
					_caching=false;
					while (e.data.length<_waveDataBytes)
					{
						e.data.writeFloat(0.0);
					}
				}
				
				_waveDataPos += _waveDataBytes;	
			}
		}
			
	
	}
}