package flump.filters;

import pixi.core.Pixi;
import pixi.core.renderers.webgl.filters.Filter;
import pixi.core.utils.Utils;

/**
 * Filter that reproduce the behaviour of Tint in Adobe Flash/Animate
 * @author Mathieu Anthoine
 */
class AnimateTintFilter extends Filter
{
	public var multiplier (default,null):Float;
	public var color (default, null):UInt;
	
	public function new(color:UInt,multiplier:Float=1) 
	{
		super(null, getFragmentSrc());
		
		uniforms.color = hex2array(color);
		uniforms.multiplier = 0.5;
	}
	
	private function getFragmentSrc ():String {
		var lSrc:String = "";
		lSrc += "precision mediump float;varying vec2 vTextureCoord;uniform sampler2D uSampler;uniform vec3 color;uniform float multiplier;";
		lSrc += "void main () { gl_FragColor = texture2D(uSampler, vTextureCoord);";
		lSrc += "gl_FragColor.rgb = mix(gl_FragColor.rgb, color.rgb, multiplier) * gl_FragColor.a;";
		lSrc += "}";
		return lSrc;
	}
	
	private function hex2array(color:UInt):Array<Float> {
		return [(color >> 16 & 0xFF) / 255, (color >> 8 & 0xFF) / 255, (color & 0xFF) / 255];
	}
	
	public function update(color:UInt, multiplier:Float = 1) : Void {
		this.color = color;
		this.multiplier = multiplier;
		
		Utils.hex2rgb(color, uniforms.color);
		uniforms.multiplier = multiplier;
	}
	
}