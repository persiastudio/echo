function tinyecho_recorder_init()
{
    global.te_recording    = false;
    global.te_queue_id     = -1;
    global.te_buffer       = -1;
    global.te_data_size    = 0;
    global.te_pending_save = false;
    global.te_save_name    = "";

    var _info = audio_get_recorder_info(0);
    global.te_sample_rate = _info[? "sample_rate"];
    global.te_channels    = _info[? "channels"];
    global.te_data_format = _info[? "data_format"];
    ds_map_destroy(_info);

    global.te_bit_depth = (global.te_data_format == buffer_f32) ? 32 : 16;

    show_debug_message("[TinyEcho] Init: " + string(global.te_sample_rate) + "Hz / " + string(global.te_channels) + "ch / " + string(global.te_bit_depth) + "bit");
}

function tinyecho_recorder_start()
{
    if global.te_recording { return false; }
    if audio_get_recorder_count() == 0
    {
        show_debug_message("[TinyEcho] Nenhum microfone encontrado.");
        return false;
    }

    global.te_sample_rate = 16000;
    global.te_channels    = 1;
    global.te_bit_depth   = 16;

    global.te_buffer    = buffer_create(1024, buffer_grow, 1);
    global.te_data_size = 0;

    buffer_seek(global.te_buffer, buffer_seek_start, 0);
    repeat(44) { buffer_write(global.te_buffer, buffer_u8, 0); }

    global.te_queue_id  = audio_start_recording(0);
    global.te_recording = true;

    show_debug_message("[TinyEcho] Gravação iniciada. Queue ID: " + string(global.te_queue_id));
    return true;
}

function tinyecho_recorder_stop(filename)
{
    if !global.te_recording { return ""; }
    audio_stop_recording(global.te_queue_id);
    global.te_recording = false;
    show_debug_message("[TinyEcho] Gravação parada. data_size: " + string(global.te_data_size));
    tinyecho_write_wav_header();
    var _dir  = UsrPath[LgdUser] + "//TinyEcho//Recordings";
    var _path = _dir + "//" + filename + ".wav";

    var _exact_size = 44 + global.te_data_size;
    var _final      = buffer_create(_exact_size, buffer_fixed, 1);
    buffer_copy(global.te_buffer, 0, _exact_size, _final, 0);
    buffer_delete(global.te_buffer);
    global.te_buffer = -1;

    buffer_save(_final, _path);
    buffer_delete(_final);
	var _check = buffer_load(_path);
	buffer_seek(_check, buffer_seek_start, 0);
	show_debug_message("[WAV] RIFF: " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)));
	show_debug_message("[WAV] chunk_size: " + string(buffer_read(_check, buffer_u32)));
	show_debug_message("[WAV] WAVE: " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)));
	show_debug_message("[WAV] fmt : " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)));
	show_debug_message("[WAV] subchunk1size: " + string(buffer_read(_check, buffer_u32)));
	show_debug_message("[WAV] audio_format: " + string(buffer_read(_check, buffer_u16)));
	show_debug_message("[WAV] channels: " + string(buffer_read(_check, buffer_u16)));
	show_debug_message("[WAV] sample_rate: " + string(buffer_read(_check, buffer_u32)));
	show_debug_message("[WAV] byte_rate: " + string(buffer_read(_check, buffer_u32)));
	show_debug_message("[WAV] block_align: " + string(buffer_read(_check, buffer_u16)));
	show_debug_message("[WAV] bit_depth: " + string(buffer_read(_check, buffer_u16)));
	show_debug_message("[WAV] data: " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)) + " " + string(buffer_read(_check, buffer_u8)));
	show_debug_message("[WAV] data_size: " + string(buffer_read(_check, buffer_u32)));
	buffer_delete(_check);

    show_debug_message("[TinyEcho] Arquivo salvo: " + _path);
    return _path;
}

function tinyecho_async_recording_event()
{
    // Chama isso no Async Event - Audio Recording do objeto controlador
    if (async_load[? "channel_index"] != global.te_queue_id) { exit; }

    var _buf  = async_load[? "buffer_id"];
    var _len  = async_load[? "data_len"];

    if global.te_buffer != -1 && _len > 0
    {
        buffer_copy(_buf, 0, _len, global.te_buffer, 44 + global.te_data_size);
        global.te_data_size += _len;
    }

    // Se parou de gravar e ainda estamos recebendo chunks, esse é o último
    if (!global.te_recording && global.te_pending_save)
    {
        global.te_pending_save = false;
        tinyecho_save_wav(global.te_save_name);
    }
}

function tinyecho_save_wav(filename)
{
    show_debug_message("[TinyEcho] Salvando WAV. data_size: " + string(global.te_data_size));

    tinyecho_write_wav_header();

    var _dir  = UsrPath[LgdUser] + "//TinyEcho//Recordings";
    var _path = _dir + "//" + filename + ".wav";

    buffer_save(global.te_buffer, _path);
    buffer_delete(global.te_buffer);
    global.te_buffer = -1;

    show_debug_message("[TinyEcho] Arquivo salvo: " + _path);
    return _path;
}

function tinyecho_write_wav_header()
{
    var _data_size   = global.te_data_size;
    var _sample_rate = global.te_sample_rate;
    var _channels    = global.te_channels;
    var _bit_depth   = global.te_bit_depth;
    var _byte_rate   = _sample_rate * _channels * (_bit_depth div 8);
    var _block_align = _channels * (_bit_depth div 8);
    var _chunk_size  = 36 + _data_size;

    buffer_seek(global.te_buffer, buffer_seek_start, 0);

    buffer_write(global.te_buffer, buffer_u8,  ord("R"));
    buffer_write(global.te_buffer, buffer_u8,  ord("I"));
    buffer_write(global.te_buffer, buffer_u8,  ord("F"));
    buffer_write(global.te_buffer, buffer_u8,  ord("F"));
    buffer_write(global.te_buffer, buffer_u32, _chunk_size);
    buffer_write(global.te_buffer, buffer_u8,  ord("W"));
    buffer_write(global.te_buffer, buffer_u8,  ord("A"));
    buffer_write(global.te_buffer, buffer_u8,  ord("V"));
    buffer_write(global.te_buffer, buffer_u8,  ord("E"));
    buffer_write(global.te_buffer, buffer_u8,  ord("f"));
    buffer_write(global.te_buffer, buffer_u8,  ord("m"));
    buffer_write(global.te_buffer, buffer_u8,  ord("t"));
    buffer_write(global.te_buffer, buffer_u8,  ord(" "));
    buffer_write(global.te_buffer, buffer_u32, 16);
    buffer_write(global.te_buffer, buffer_u16, 1);   // AudioFormat 1 = PCM
    buffer_write(global.te_buffer, buffer_u16, _channels);
    buffer_write(global.te_buffer, buffer_u32, _sample_rate);
    buffer_write(global.te_buffer, buffer_u32, _byte_rate);
    buffer_write(global.te_buffer, buffer_u16, _block_align);
    buffer_write(global.te_buffer, buffer_u16, _bit_depth);
    buffer_write(global.te_buffer, buffer_u8,  ord("d"));
    buffer_write(global.te_buffer, buffer_u8,  ord("a"));
    buffer_write(global.te_buffer, buffer_u8,  ord("t"));
    buffer_write(global.te_buffer, buffer_u8,  ord("a"));
    buffer_write(global.te_buffer, buffer_u32, _data_size);
}

function tinyecho_playback_start(filepath)
{
    var _raw = buffer_load(filepath);
    if _raw == -1
    {
        show_debug_message("[TinyEcho] Erro ao carregar: " + filepath);
        return -1;
    }

    buffer_seek(_raw, buffer_seek_start, 40);
    var _size        = buffer_read(_raw, buffer_u32);
    var _frame_size  = global.te_channels * 2; // s16 = 2 bytes
    var _aligned     = (_size div _frame_size) * _frame_size; // alinha ao frame

    var _buffer = buffer_create(_aligned, buffer_fixed, 1);
    buffer_copy(_raw, 44, _aligned, _buffer, 0);
    buffer_delete(_raw);

    var _sound = audio_create_buffer_sound(
        _buffer,
        buffer_s16,
        global.te_sample_rate,
        0,
        _aligned,
        global.te_channels == 2 ? audio_stereo : audio_mono
    );

    if _sound == -1
    {
        show_debug_message("[TinyEcho] Erro ao criar som.");
        buffer_delete(_buffer);
        return -1;
    }

    var _inst = audio_play_sound(_sound, 1, false);
    show_debug_message("[TinyEcho] Reproduzindo: " + filepath);
    return { sound: _sound, buffer: _buffer, instance: _inst };
}

function tinyecho_playback_stop(playback)
{
    if audio_is_playing(playback.instance)
    {
        audio_stop_sound(playback.instance);
    }
    audio_free_buffer_sound(playback.sound);
    buffer_delete(playback.buffer);
    show_debug_message("[TinyEcho] Reprodução parada e memória liberada.");
}
