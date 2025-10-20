-- {"query": "34025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1094} 

WITH RankedAnswers AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswers AS (
    SELECT AnswerId, QuestionId, AnswerScore, AnswerCreationDate
    FROM RankedAnswers
    WHERE AnswerRank = 1
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCount,
        MAX(b.Date) FILTER (WHERE b.Class = 1) AS MostRecentGoldBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 2) AS MostRecentSilverBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 3) AS MostRecentBronzeBadgeDate
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE q.PostTypeId = 1 AND q.CreationDate >= CURRENT_DATE - INTERVAL '3 year'
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, u.Id, u.DisplayName, u.Reputation
),
AnswerWithUser AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        au.Id AS AnswerOwnerUserId,
        au.DisplayName AS AnswerOwnerDisplayName,
        au.Reputation AS AnswerOwnerReputation
    FROM Posts a
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    WHERE a.PostTypeId = 2
),
DetailedResults AS (
    SELECT
        qs.QuestionId,
        qs.Title,
        qs.QuestionCreationDate,
        qs.QuestionScore,
        qs.ViewCount,
        qs.OwnerUserId,
        qs.OwnerDisplayName,
        qs.OwnerReputation,
        qs.CommentCount,
        qs.UpVotesCount,
        qs.DownVotesCount,
        qs.MostRecentGoldBadgeDate,
        qs.MostRecentSilverBadgeDate,
        qs.MostRecentBronzeBadgeDate,
        ta.AnswerId,
        ta.AnswerScore,
        ta.AnswerCreationDate,
        awu.AnswerOwnerUserId,
        awu.AnswerOwnerDisplayName,
        awu.AnswerOwnerReputation,
        EXTRACT(EPOCH FROM (ta.AnswerCreationDate - qs.QuestionCreationDate))/3600 AS HoursToTopAnswer,
        CASE 
            WHEN qs.OwnerReputation > 10000 THEN 'Expert'
            WHEN qs.OwnerReputation BETWEEN 1000 AND 10000 THEN 'Intermediate'
            ELSE 'Novice'
        END AS OwnerReputationLevel
    FROM QuestionStats qs
    LEFT JOIN TopAnswers ta ON ta.QuestionId = qs.QuestionId
    LEFT JOIN AnswerWithUser awu ON awu.AnswerId = ta.AnswerId
),
TagCounts AS (
    SELECT
        unnest(string_to_array(substring(Tags from 2 for length(Tags)-2), '><')) AS Tag
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
),
PopularTags AS (
    SELECT Tag, COUNT(*) AS UsageCount
    FROM TagCounts
    GROUP BY Tag
    ORDER BY UsageCount DESC
    LIMIT 20
)
SELECT 
    dr.OwnerReputationLevel,
    dr.Title,
    dr.QuestionCreationDate,
    dr.QuestionScore,
    dr.ViewCount,
    dr.CommentCount,
    dr.UpVotesCount,
    dr.DownVotesCount,
    dr.MostRecentGoldBadgeDate,
    dr.MostRecentSilverBadgeDate,
    dr.MostRecentBronzeBadgeDate,
    dr.AnswerId,
    dr.AnswerScore,
    dr.AnswerCreationDate,
    dr.AnswerOwnerUserId,
    dr.AnswerOwnerDisplayName,
    dr.AnswerOwnerReputation,
    dr.HoursToTopAnswer,
    pt.Tag AS PopularTag,
    pt.UsageCount AS TagUsageCount
FROM DetailedResults dr
CROSS JOIN LATERAL (
    SELECT Tag, UsageCount
    FROM PopularTags
    ORDER BY random()
    LIMIT 1
) pt
WHERE dr.AnswerScore IS NOT NULL
ORDER BY dr.OwnerReputationLevel DESC, dr.QuestionScore DESC, dr.HoursToTopAnswer
LIMIT 100;
