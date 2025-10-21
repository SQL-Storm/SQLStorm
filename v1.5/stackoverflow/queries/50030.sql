-- {"query": "50030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1081} 
WITH UserMetrics AS (
    -- Select active, high-reputation users with at least one gold badge
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        MIN(b.Date) AS FirstGoldBadgeDate
    FROM
        Users u
    JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY Reputation) FROM Users)
        AND u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
        AND b.Class = 1 -- Gold badges
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate
),
AnswerDetails AS (
    -- Gather details for every answer posted by these users, including its rank among other answers to the same question
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        q.Id AS QuestionId,
        q.Tags AS QuestionTags,
        q.ViewCount AS QuestionViewCount,
        q.CreationDate AS QuestionCreationDate,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600 AS HoursToAnswer,
        RANK() OVER(PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerCommentCount
    FROM
        Posts a
    JOIN
        Posts q ON a.ParentId = q.Id
    WHERE
        a.PostTypeId = 2 -- Answers
        AND a.OwnerUserId IN (SELECT Id FROM UserMetrics)
),
UserTagContribution AS (
    -- Determine the most frequent tag each user has answered questions for
    SELECT
        OwnerUserId,
        Tag,
        TagCount,
        ROW_NUMBER() OVER(PARTITION BY OwnerUserId ORDER BY TagCount DESC, Tag ASC) as rn
    FROM (
        SELECT
            ad.OwnerUserId,
            unnest(string_to_array(substring(ad.QuestionTags, 2, length(ad.QuestionTags) - 2), '><')) AS Tag,
            COUNT(*) as TagCount
        FROM AnswerDetails ad
        GROUP BY ad.OwnerUserId, Tag
    ) AS TagCounts
)
-- Final aggregation to produce a leaderboard of these 'power users'
SELECT
    um.DisplayName,
    um.Reputation,
    CAST(um.UpVotes AS REAL) / GREATEST(um.DownVotes, 1) AS VoteRatio,
    EXTRACT(DAY FROM (cast('2024-10-01 12:34:56' as timestamp) - um.UserCreationDate)) AS MembershipDays,
    EXTRACT(DAY FROM (um.FirstGoldBadgeDate - um.UserCreationDate)) AS DaysToFirstGold,
    COUNT(ad.AnswerId) AS TotalAnswers,
    SUM(ad.IsAccepted) AS AcceptedAnswers,
    CAST(SUM(ad.IsAccepted) AS REAL) / COUNT(ad.AnswerId) AS AcceptedAnswerRate,
    AVG(ad.AnswerScore) AS AverageAnswerScore,
    MAX(ad.AnswerScore) AS MaxAnswerScore,
    AVG(ad.HoursToAnswer) AS AverageHoursToAnswer,
    SUM(CASE WHEN ad.AnswerRank = 1 THEN 1 ELSE 0 END) AS TopRankedAnswers,
    CAST(SUM(CASE WHEN ad.AnswerRank = 1 THEN 1 ELSE 0 END) AS REAL) / COUNT(ad.AnswerId) AS TopRankedAnswerRate,
    AVG(ad.AnswerCommentCount) AS AvgCommentsPerAnswer,
    SUM(ad.QuestionViewCount) AS TotalQuestionViewsImpacted,
    utc.Tag AS MostFrequentTag,
    utc.TagCount AS MostFrequentTagAnswers
FROM
    UserMetrics um
JOIN
    AnswerDetails ad ON um.Id = ad.OwnerUserId
JOIN
    UserTagContribution utc ON um.Id = utc.OwnerUserId AND utc.rn = 1
GROUP BY
    um.DisplayName,
    um.Reputation,
    VoteRatio,
    MembershipDays,
    DaysToFirstGold,
    utc.Tag,
    utc.TagCount
HAVING
    COUNT(ad.AnswerId) > 50 -- Only show users with a significant number of answers
ORDER BY
    um.Reputation DESC,
    AcceptedAnswerRate DESC
LIMIT 100;