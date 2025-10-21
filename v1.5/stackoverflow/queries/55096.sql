WITH exploded_tags AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_stats AS (
    SELECT
        e.Tag,
        COUNT(*) AS QuestionCount,
        AVG(e.Score) AS AvgQuestionScore,
        AVG(e.AnswerCount) AS AvgAnswersPerQuestion,
        SUM(e.ViewCount) AS TotalViews,
        MAX(e.CreationDate) AS MostRecentQuestionDate
    FROM exploded_tags e
    GROUP BY e.Tag
),
user_activity AS (
    SELECT
        e.Tag,
        e.OwnerUserId,
        COUNT(*) AS QuestionsAsked,
        SUM(e.Score) AS TotalQuestionScore,
        SUM(e.AnswerCount) AS TotalAnswersReceived,
        RANK() OVER (PARTITION BY e.Tag ORDER BY SUM(e.Score) DESC) AS ScoreRank
    FROM exploded_tags e
    GROUP BY e.Tag, e.OwnerUserId
),
vote_agg AS (
    SELECT
        p.Id AS PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
combined AS (
    SELECT
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.AvgAnswersPerQuestion,
        ts.TotalViews,
        ts.MostRecentQuestionDate,
        ua.OwnerUserId,
        ua.QuestionsAsked,
        ua.TotalQuestionScore,
        ua.TotalAnswersReceived,
        ua.ScoreRank,
        va.UpVotes,
        va.DownVotes,
        va.Favorites
    FROM tag_stats ts
    LEFT JOIN user_activity ua ON ua.Tag = ts.Tag
    LEFT JOIN exploded_tags e ON e.Tag = ts.Tag AND e.OwnerUserId = ua.OwnerUserId
    LEFT JOIN vote_agg va ON va.PostId = e.PostId
)
SELECT *
FROM combined
WHERE ScoreRank <= 5
ORDER BY Tag, ScoreRank;