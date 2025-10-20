-- {"query": "28046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1699} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)), 0) AS PostScoreSum,
        AVG(LENGTH(p.Body)) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionLength
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
),
ClosedPosts AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE cht.Name = 'Duplicate') AS DuplicateClosures,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE cht.Name = 'Off-topic') AS OfftopicClosures
    FROM PostHistory ph
    JOIN CloseReasonTypes cht ON ph.Comment::int = cht.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId
),
TagExperts AS (
    SELECT
        p.OwnerUserId AS UserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagUseCount,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
)
SELECT 
    u.Id,
    u.DisplayName,
    us.BadgeCount,
    us.QuestionCount,
    us.AnswerCount,
    (us.PostScoreSum * 0.5 + us.UpvotesGiven * 0.3 + us.CommentCount * 0.2) AS ActivityScore,
    COALESCE(cp.DuplicateClosures, 0) + COALESCE(cp.OfftopicClosures, 0) AS TotalClosures,
    (SELECT AVG(AnswerCount) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) AS AvgAnswersPerQuestion,
    (SELECT STRING_AGG(te.TagName, ', ' ORDER BY te.TagUseCount DESC) 
     FROM TagExperts te 
     WHERE te.UserId = u.Id AND te.TagRank <= 3) AS TopTags,
    ROW_NUMBER() OVER (ORDER BY us.PostScoreSum DESC) AS GlobalRank,
    NTILE(4) OVER (ORDER BY u.Reputation) AS ReputationQuartile,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.AcceptedAnswerId IS NOT NULL)
        THEN LEAST(us.AvgQuestionLength * 0.1, 100)
        ELSE 0
    END AS QuestionQualityIndex
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN ClosedPosts cp ON u.Id = cp.UserId
WHERE u.Reputation > 1000
    AND u.CreationDate BETWEEN '2010-01-01' AND '2020-01-01'
    AND (us.QuestionCount > 10 OR us.AnswerCount > 50)
ORDER BY ActivityScore DESC
LIMIT 100;
