/// The chat subsystem's ioctl command numbers — fixed by
/// `chatinference-subsystem.md` ("ioctl Codec" table). Shared vocabulary
/// between the device layer (issues them) and drivers (dispatch them).
library;

const chatSetMaxTokens = 0x01;
const chatSetTemperature = 0x02;
const chatSetTopP = 0x03;
const chatSetStop = 0x04;
const chatSetReasoningBudget = 0x05;
const chatSetInputFormat = 0x06;
const chatSetOutputFormat = 0x07;
const chatSetFunctions = 0x08;
const chatSetFunctionChoice = 0x09;
const chatSetExtra = 0x0A;
const chatSetFirstRole = 0x0B;
const chatSetStreaming = 0x0C;

const chatGetMetadata = 0x80;
const chatGetError = 0x81;
const chatGetInfo = 0x82;
