-- {"query": "2012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1571} 

WITH RecursiveTagPosts AS (
    -- Find all questions with tags containing 'sql' or similar, recursively joined with their answers and related posts
    SELECT p.Id, p.PostTypeId, p.Title, p.Tags, p.CreationDate, p.OwnerUserId, 0 AS Level
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags ILIKE '%<sql>%'

    UNION ALL

    SELECT c.Id, c.PostTypeId, c.Title, c.Tags, c.CreationDate, c.OwnerUserId, r.Level + 1
    FROM Posts c
    INNER JOIN RecursiveTagPosts r ON (c.ParentId = r.Id OR c.Id = r.Id)
    WHERE c.PostTypeId IN (1,2) AND r.Level < 3
),
RankedUsers AS (
    -- Ranking users by reputation weighted by post score and their badge achievements with complex string aggregation
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        SUM(COALESCE(p.Score,0)) AS TotalPostScore,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT CONCAT(b.Name, '(', b.Class, ')'), ', ' ORDER BY b.Class, b.Name) AS BadgeList,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, TotalPostScore DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.Score > 0
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopQuestionsCTE AS (
    -- Select top 20 questions by combined window function score and answered status, with complicated predicates
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.AcceptedAnswerId,
        RANK() OVER (PARTITION BY p.CreationDate::date ORDER BY p.Score DESC, p.ViewCount DESC) AS DailyRank,
        COUNT(q.Id) OVER () AS TotalQuestions,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        -- Use string length, NULL logic and complex expression to score tags
        COALESCE(NULLIF(LENGTH(p.Tags), 0), 0) * p.Score / NULLIF((p.AnswerCount + 1),0) AS TagScoreRatio
    FROM Posts p
    LEFT JOIN Posts q ON q.ParentId = p.Id AND q.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND (p.ClosedDate IS NULL OR p.ClosedDate > NOW() - INTERVAL '30 days')
      AND p.Score > 0
      AND (p.Tags ILIKE '%<sql>%' OR p.Tags ILIKE '%<performance>%')
),
AnswersWithVotes AS (
    -- Correlated subquery for each answer to calculate votes with complex NULL logic and outer join
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS NetVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score
),
FinalAggregated AS (
    -- Aggregate data combining questions and answers with complex CASE and set operator (UNION ALL with filters)
    SELECT
        tq.QuestionId,
        tq.Title,
        tq.Tags,
        tq.Score AS QuestionScore,
        tq.ViewCount,
        tq.AnswerCount,
        tq.HasAcceptedAnswer,
        au.UserRank AS QuestionOwnerRank,
        au.Reputation AS QuestionOwnerReputation,
        AVG(av.NetVotes) FILTER (WHERE av.QuestionId = tq.QuestionId) OVER (PARTITION BY tq.QuestionId) AS AvgAnswerNetVotes,
        COUNT(av.AnswerId) FILTER (WHERE av.QuestionId = tq.QuestionId AND av.NetVotes > 0) AS PositiveAnswersCount,
        CASE
            WHEN tq.AnswerCount > 5 THEN 'High Activity'
            WHEN tq.AnswerCount BETWEEN 1 AND 5 THEN 'Moderate Activity'
            ELSE 'Low Activity'
        END AS ActivityLevel
    FROM TopQuestionsCTE tq
    LEFT JOIN Posts u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = tq.QuestionId)
    LEFT JOIN RankedUsers au ON au.Id = u.OwnerUserId
    LEFT JOIN AnswersWithVotes av ON av.QuestionId = tq.QuestionId
),
DuplicatedQuestions AS (
    -- Using set operator EXCEPT to find questions which are not duplicates of others based on PostLinks
    SELECT p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1

    EXCEPT

    SELECT pl.PostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate link type
)
SELECT
    fa.QuestionId,
    fa.Title,
    fa.Tags,
    fa.QuestionScore,
    fa.ViewCount,
    fa.AnswerCount,
    fa.HasAcceptedAnswer,
    fa.QuestionOwnerRank,
    fa.QuestionOwnerReputation,
    fa.AvgAnswerNetVotes,
    fa.PositiveAnswersCount,
    fa.ActivityLevel,
    dt.Id AS NonDuplicateQuestionId,
    ru.DisplayName AS TopUserDisplayName,
    ru.BadgeList,
    rp.Level AS TagPostHierarchyLevel,
    CONCAT(
        COALESCE(u.Location, 'Unknown'), ' / ', 
        COALESCE(u.WebsiteUrl, 'No Website')
    ) AS UserLocationWebsite,
    -- Complex string expressions
    SUBSTRING(fa.Title FROM 1 FOR 50) || '...' AS ShortTitle,
    CASE
        WHEN fa.ActivityLevel = 'High Activity' THEN '🔥 Hot'
        WHEN fa.ActivityLevel = 'Moderate Activity' THEN '✨ Active'
        ELSE '❄️ Quiet'
    END AS ActivityEmoji
FROM FinalAggregated fa
LEFT JOIN DuplicatedQuestions dt ON dt.Id = fa.QuestionId
LEFT JOIN RankedUsers ru ON ru.Id = (SELECT OwnerUserId FROM Posts WHERE Id = fa.QuestionId)
LEFT JOIN RecursiveTagPosts rp ON rp.Id = fa.QuestionId
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = fa.QuestionId)
WHERE dt.Id IS NOT NULL
  AND (fa.AvgAnswerNetVotes IS NULL OR fa.AvgAnswerNetVotes > 0)
ORDER BY fa.QuestionScore DESC, fa.ViewCount DESC, fa.PositiveAnswersCount DESC
LIMIT 50;
