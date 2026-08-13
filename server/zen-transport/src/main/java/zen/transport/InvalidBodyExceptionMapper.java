package zen.transport;

import com.google.protobuf.InvalidProtocolBufferException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import zen.proto.v1.ZenError;

/**
 * Maps a malformed request body on either codec to a 400 {@code ZenError}, instead of the
 * unmapped 500 that {@code ProtoJsonMessageBodyReader} and {@code ProtobufMessageBodyReader}
 * produced before this mapper existed (2026-08-13 architectural security review, F7). Both
 * readers surface a bad body as {@link InvalidProtocolBufferException}: the protobuf path throws
 * it directly from {@code Message.Builder#mergeFrom}, and the JSON path from {@code
 * JsonFormat.Parser#merge} — its {@code Reader} overload is declared to throw the broader {@code
 * IOException}, but what it actually throws for malformed JSON is this narrower type, so a
 * mapper registered for it alone covers both readers.
 *
 * <p>Ships in {@code zen-transport}, the module that owns both readers and is already
 * Jandex-indexed (see {@code verify:modules}, F9), so every application inherits this the same
 * way it inherits the codecs themselves.
 *
 * <p>The message names the codec and says nothing about the parser's internals — no field path,
 * no byte offset, no exception class name, none of the stack trace {@code %dev} was leaking into
 * the response body before this mapper existed. No explicit media type is set on the response:
 * {@code ZenTransportFilter} already rewrote {@code Accept} pre-matching, so the same {@code
 * ProtobufMessageBodyWriter} / {@code ProtoJsonMessageBodyWriter} negotiation that renders a
 * successful response renders this {@code ZenError} in whichever format the caller
 * negotiated — see {@code AuthExceptionMapper} in {@code zen-identity} for the identical pattern.
 */
@Provider
public class InvalidBodyExceptionMapper implements ExceptionMapper<InvalidProtocolBufferException> {

  @Override
  public Response toResponse(InvalidProtocolBufferException exception) {
    ZenError error =
        ZenError.newBuilder()
            .setCode("invalid_body")
            .setMessage("The request body could not be parsed as the negotiated transport format.")
            .build();
    return Response.status(Response.Status.BAD_REQUEST).entity(error).build();
  }
}
