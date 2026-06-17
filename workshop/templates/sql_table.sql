GO
IF OBJECT_ID('[dbo].[Articles]', 'U') IS NOT NULL
BEGIN
	PRINT 'Table exists.'
END
ELSE
BEGIN

	SET ANSI_NULLS ON
	SET QUOTED_IDENTIFIER ON

	CREATE TABLE [dbo].[Articles](
		[id] [smallint] NOT NULL,
		[author] [nvarchar](150) NULL,
		[claps] [nvarchar](50) NULL,
		[reading_time] [tinyint] NULL,
		[link] [nvarchar](500) NULL,
		[title] [nvarchar](500) NULL,
		[text] [nvarchar](max) NULL
	CONSTRAINT [PK_Articles] PRIMARY KEY CLUSTERED 
	(
		[id] ASC
	)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
	) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

END


