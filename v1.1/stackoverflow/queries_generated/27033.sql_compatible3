WITH ActiveUsers AS (
    SELECT
        Id,
        Reputation,
        CreationDate,
        DisplayName,
        LastAccessDate,
        NULLIF(WebsiteUrl, '') AS WebsiteUrl,
        NULLIF(Location, '') AS Location,
        LENGTH(COALESCE(AboutMe, '')) AS AboutMeLength,
        Views,
        UpVotes,
        DownVotes,
        -- EmailHash removed because column does not exist
        CASE
            WHEN ProfileImageUrl IS NOT NULL THEN
                CASE WHEN ProfileImageUrl LIKE 'http://%' OR ProfileImageUrl LIKE 'https://%' THEN ProfileImageUrl ELSE 'NoImageUrl' END
            ELSE 'NoImageUrl'
        END AS Domain,
        NULLIF(AccountId, 0) AS AccountId
    FROM
        Users
    WHERE
        LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
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
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes
    FROM
        Votes v
    JOIN
        Posts p ON v.PostId = p.Id
    GROUP BY
        p.Id,
        p.OwnerUserId
    HAVING
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) > 50
),

TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(p.AnswerCount) AS TotalAnswers,
        SUM(p.ViewCount) AS TotalViews,
        FLOOR(COUNT(p.Id) * 0.01) AS CountPercentage
    FROM
        Tags t
    JOIN
        Posts p ON p.Tags LIKE ('%><' || t.TagName || '><%')
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
    s.TotalAnswers AS AnswersInTag,
    s.TotalViews AS ViewsOfTag
FROM
    ActiveUsers au
LEFT JOIN
    ProlificPosters pp ON au.Id = pp.UserId
LEFT JOIN LATERAL
    (
        SELECT
            hv_inner.PostId,
            hv_inner.UserId,
            hv_inner.NetVotes
        FROM HighVotes hv_inner
        WHERE hv_inner.UserId = au.Id
        ORDER BY hv_inner.NetVotes DESC, hv_inner.PostId
        LIMIT 1
    ) hv ON TRUE
LEFT JOIN LATERAL
    (
        SELECT
            s_inner.TagName,
            s_inner.QuestionCount,
            s_inner.TotalAnswers,
            s_inner.TotalViews,
            s_inner.CountPercentage
        FROM TagStats s_inner
        WHERE s_inner.TagName LIKE '%Info%'
        ORDER BY s_inner.CountPercentage DESC, s_inner.TagName
        LIMIT 1
    ) s ON s.TagName LIKE COALESCE(au.WebsiteUrl, '')

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
    s.TotalAnswers AS AnswersInTag,
    s.TotalViews AS ViewsOfTag
FROM
    ActiveUsers au
LEFT JOIN
    ProlificPosters pp ON au.Id = pp.UserId
LEFT JOIN LATERAL
    (
        SELECT
            hv_inner.PostId,
            hv_inner.UserId,
            hv_inner.NetVotes
        FROM HighVotes hv_inner
        WHERE hv_inner.UserId = au.Id
        ORDER BY hv_inner.NetVotes ASC, hv_inner.PostId
        LIMIT 1
    ) hv ON TRUE
LEFT JOIN LATERAL
    (
        SELECT
            s_inner.TagName,
            s_inner.QuestionCount,
            s_inner.TotalAnswers,
            s_inner.TotalViews,
            s_inner.CountPercentage
        FROM TagStats s_inner
        WHERE s_inner.TagName LIKE '%number%'
        ORDER BY s_inner.CountPercentage ASC, s_inner.TagName
        LIMIT 1
    ) s ON s.TagName LIKE COALESCE(au.Location, '')
ORDER BY
    TotalAnswers ASC,
    NetVotes;