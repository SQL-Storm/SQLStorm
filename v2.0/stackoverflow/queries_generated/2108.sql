-- {"query": "2108.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1781} 

WITH RecursiveUserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        b.TagBased,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC, b.Class) AS RecentBadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.LastActivityDate,
        -- Extract array of tags
        string_to_array(
            substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2),
            '><'
        ) AS TagArray
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1  -- Questions only
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
      AND (p.ClosedDate IS NULL OR p.ClosedDate > NOW() - INTERVAL '3 month')
),
PostLinkCounts AS (
    SELECT
        PostId,
        COUNT(CASE WHEN LinkTypeId = 1 THEN 1 END) AS LinkedCount,
        COUNT(CASE WHEN LinkTypeId = 3 THEN 1 END) AS DuplicateCount
    FROM PostLinks
    GROUP BY PostId
),
TopAnswerers AS (
    SELECT
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY COUNT(*) DESC, AVG(p.Score) DESC) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2 -- Answers
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.ParentId, p.OwnerUserId
),
AcceptedAnswerInfo AS (
    SELECT
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswererName
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
QuestionCommentsCount AS (
    SELECT
        PostId,
        COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
),
CloseReasonsCount AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS DistinctCloseReasonsCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserReputationRanks AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
    WHERE Reputation > 0
),
QuestionsWithDetails AS (
    SELECT
        fp.Id,
        fp.Title,
        fp.CreationDate,
        fp.Score,
        fp.ViewCount,
        fp.AnswerCount,
        fp.Tags,
        fp.OwnerUserId,
        fp.OwnerName,
        plc.LinkedCount,
        plc.DuplicateCount,
        qc.CommentCount,
        cr.CloseVotesCount,
        cr.DistinctCloseReasonsCount,
        aa.AnswerScore AS AcceptedAnswerScore,
        aa.AnswerCreationDate AS AcceptedAnswerDate,
        aa.AnswererName AS AcceptedAnswererName
    FROM FilteredPosts fp
    LEFT JOIN PostLinkCounts plc ON fp.Id = plc.PostId
    LEFT JOIN QuestionCommentsCount qc ON fp.Id = qc.PostId
    LEFT JOIN CloseReasonsCount cr ON fp.Id = cr.PostId
    LEFT JOIN AcceptedAnswerInfo aa ON fp.AcceptedAnswerId = aa.AnswerId
),
QuestionsWithTopAnswerers AS (
    SELECT
        qwd.*,
        ta.AnswererId,
        ta.AnswerCount AS TopAnswererAnswerCount,
        ta.AvgAnswerScore AS TopAnswererAvgScore
    FROM QuestionsWithDetails qwd
    LEFT JOIN TopAnswerers ta ON qwd.Id = ta.QuestionId AND ta.AnswerRank = 1
),
FinalAggregated AS (
    SELECT
        q.Id,
        q.Title,
        q.CreationDate,
        ROUND(q.Score * 1.0 / NULLIF(q.ViewCount,0),4) AS ScorePerView,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        q.OwnerUserId,
        q.OwnerName,
        COALESCE(q.LinkedCount,0) AS LinkedCount,
        COALESCE(q.DuplicateCount,0) AS DuplicateCount,
        COALESCE(q.CommentCount,0) AS CommentCount,
        COALESCE(q.CloseVotesCount,0) AS CloseVotesCount,
        COALESCE(q.DistinctCloseReasonsCount,0) AS DistinctCloseReasonsCount,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerDate,
        q.AcceptedAnswererName,
        q.AnswererId AS TopAnswererId,
        q.TopAnswererAnswerCount,
        q.TopAnswererAvgScore,
        ur.Reputation AS TopAnswererReputation,
        ur.DisplayName AS TopAnswererName,
        -- Complex calculated field: weighted engagement score
        (
            (q.Score * 3) +
            (q.ViewCount / NULLIF(LEAST(EXTRACT(EPOCH FROM (NOW() - q.CreationDate))/86400, 365),0)) * 2 +
            (q.AnswerCount * 5) +
            (COALESCE(q.CommentCount,0) * 1.5) -
            (COALESCE(q.CloseVotesCount,0) * 10)
        ) * GREATEST(1, LOG(10, NULLIF(q.Score,1))) AS WeightedEngagementScore,
        -- String expression with NULL logic (concatenate owner and accepted answerer names)
        COALESCE(q.OwnerName, 'Anonymous') || ' | Accepted Answer by: ' || COALESCE(q.AcceptedAnswererName, 'None') AS OwnerAcceptedAnswerer,
        -- Window function to rank by weighted engagement within tag groups
        ROW_NUMBER() OVER (
            PARTITION BY unnest(string_to_array(q.Tags, '><')) 
            ORDER BY 
                (
                    (q.Score * 3) +
                    (q.ViewCount / NULLIF(LEAST(EXTRACT(EPOCH FROM (NOW() - q.CreationDate))/86400, 365),0)) * 2 +
                    (q.AnswerCount * 5) +
                    (COALESCE(q.CommentCount,0) * 1.5) -
                    (COALESCE(q.CloseVotesCount,0) * 10)
                ) * GREATEST(1, LOG(10, NULLIF(q.Score,1)))
            DESC
        ) AS TagWeightedRank
    FROM QuestionsWithTopAnswerers q
    LEFT JOIN Users ur ON q.AnswererId = ur.Id
)
SELECT DISTINCT
    fa.Id AS QuestionId,
    fa.Title,
    fa.CreationDate,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.LinkedCount,
    fa.DuplicateCount,
    fa.CommentCount,
    fa.CloseVotesCount,
    fa.DistinctCloseReasonsCount,
    fa.AcceptedAnswerScore,
    fa.AcceptedAnswerDate,
    fa.OwnerAcceptedAnswerer,
    fa.TopAnswererAnswerCount,
    fa.TopAnswererAvgScore,
    fa.TopAnswererReputation,
    fa.WeightedEngagementScore,
    fa.TagWeightedRank,
    tag.TagName AS Tag
FROM FinalAggregated fa
JOIN Tags tag ON tag.TagName = ANY(string_to_array(fa.Tags, '><'))
WHERE fa.Score > 5
  AND fa.ViewCount > 100
  AND (fa.CloseVotesCount = 0 OR fa.CloseVotesCount IS NULL)
  AND fa.TagWeightedRank <= 3
ORDER BY fa.WeightedEngagementScore DESC, fa.ViewCount DESC
LIMIT 100;
