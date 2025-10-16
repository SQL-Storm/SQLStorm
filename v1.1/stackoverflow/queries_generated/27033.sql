-- {"query": "27033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1338} 

WITH ActiveUsers AS (
    SELECT
        Id,
        Reputation,
        CreationDate,
        DisplayName,
        LastAccessDate,
		NullIf(WebsiteUrl, '') AS WebsiteUrl,
        NullIf(Location, '') AS Location,
        length(COALESCE(AboutMe, '')) AS AboutMeLength,
        Views,
        UpVotes,
        DownVotes,
        EmailHash,
        CASE
            WHEN ProfileImageUrl IS NOT NULL THEN substring(ProfileImageUrl from '^http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+$')
            ELSE 'NoImageUrl'
        END AS Domain,
        NullIf(AccountId, 0) AS AccountId
    FROM
        Users
    WHERE
        LastAccessDate > NOW() - INTERVAL '30 days'
),

ProlificPosters AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(*) AS PostCount,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(Score) AS TotalScore
    FROM
        Posts
    GROUP BY
        OwnerUserId
    HAVING
        COUNT(*) > 100
),

HighVotes AS (
SELECT
	PostId,
	UserID,
	SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes
FROM
	Votes v
JOIN
	Posts p ON v.PostId = p.Id
GROUP BY
	PostId,
	UserID
HAVING
	NetVotes > 50
),

TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(p.AnswerCount) AS TotalAnswers,
        SUM(p.ViewCount) AS TotalViews,
		Floor(COUNT(p.Id) *0.01) AS CountPercentage
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE CONCAT('%><', t.TagName, '><%')
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
)

SELECT
    au.Id AS UserId,
    au.Reputation,
    au.DisplayName,
    COALESCE(pp.PostCount, 0) AS TotalPosts,
    COALESCE(pp.QuestionCount, 0) AS TotalQuestions,
    COALESCE(pp.AnswerCount, 0) AS TotalAnswers,
    COALESCE(pp.TotalScore, 0) AS TotalPostScore,
	COALESCE(hv.NetVotes, 0) AS NetVotes,
    au.Views AS ProfileViews,
    au.UpVotes AS ProfileUpVotes,
    au.DownVotes AS ProfileDownVotes,
s.QuestionCount AS AskedInTag,
s.TotalAnswers AS AnswersInTag
s.ViewCount AS ViewsOfTag
FROM
    ActiveUsers au
LEFT JOIN
    ProlificPosters pp ON au.Id = pp.UserId
JOIN Lateral
    (Select *
    FROM HighVotes
	Order by NetVotes desc
 	Limit 1
    ) hv ON hv.UserId = au.Id
Join Lateral
    (Select *
    FROM TagStats
    Where TagName like '%Info%'-- pointless exit node due to the name being similar for bunch of tags
 	Order by CountPercentage desc
 	Limit 1
    ) s ON s.TagName Like au.WebsiteUrl

順位
UNION

SELECT
    au.Id AS UserId,
    au.Reputation,
    au.DisplayName,
    COALESCE(pp.PostCount, 0) AS TotalPosts,
    COALESCE(pp.QuestionCount, 0) AS TotalQuestions,
    COALESCE(pp.AnswerCount, 0) AS TotalAnswers,
    COALESCE(pp.TotalScore, 0) AS TotalPostScore,
COALESCE(hv.NetVotes, 0) AS NetVotes,
    au.Views AS ProfileViews,
    au.UpVotes AS ProfileUpVotes,
    au.DownVotes AS ProfileDownVotes,

s.QuestionCount AS AskedInTag,
s.TotalAnswers AS AnswersInTag
s.ViewCount AS ViewsOfTag

FROM
    ActiveUsers au
LEFT JOIN
    ProlificPosters pp ON au.Id = pp.UserId
Join Lateral (Select * FROM HighVotes Order by NetVotes asc Limit 1) hv ON hv.UserId = au.Id
Join Lateral (Select *
		FROM TagStats
 Where TagName like '%number%'
Order by CountPercentage asc
		Limit 1)
 s ON s.TagName Like au.Location
ORDER BY TotalAnswers ASC, NetVotes;
