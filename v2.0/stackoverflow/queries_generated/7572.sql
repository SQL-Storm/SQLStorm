-- {"query": "7572.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2147} 
WITH UserStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           u.Views,
           u.UpVotes,
           u.DownVotes,
           COUNT(DISTINCT p.Id) AS PostCount,
           COUNT(DISTINCT c.Id) AS CommentCount,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           MAX(p.CreationDate) AS LatestPostDate,
           MAX(c.CreationDate) AS LatestCommentDate,
           MAX(b.Date) AS LatestBadgeDate,
           CASE 
               WHEN u.Reputation >= 10000 THEN 'Elite'
               WHEN u.Reputation >= 1000 THEN 'Veteran'
               WHEN u.Reputation >= 100 THEN 'Regular'
               ELSE 'Newbie'
           END AS ReputationTier,
           COALESCE(SUM(p.Score), 0) AS TotalScore,
           COALESCE(SUM(p.ViewCount), 0) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY TotalScore DESC, TotalViews DESC) AS RankByScore,
           DENSE_RANK() OVER (ORDER BY Reputation DESC) AS RankByReputation,
           RANK() OVER (PARTITION BY ReputationTier ORDER BY TotalScore DESC) AS RankByTier
    FROM UserStats
),
TopPosts AS (
    SELECT p.Id AS PostId,
           p.Title,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           p.OwnerUserId,
           u.DisplayName AS OwnerName,
           COALESCE(p.AnswerCount, 0) AS AnswerCount,
           COALESCE(p.CommentCount, 0) AS CommentCount,
           CASE 
               WHEN p.PostTypeId = 1 THEN 'Question'
               WHEN p.PostTypeId = 2 THEN 'Answer'
               WHEN p.PostTypeId = 3 THEN 'Wiki'
               ELSE 'Other'
           END AS PostType,
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
           DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) AS RecentRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 0
),
PostsWithTags AS (
    SELECT tp.PostId,
           tp.Title,
           tp.Score,
           tp.ViewCount,
           tp.CreationDate,
           tp.OwnerName,
           tp.AnswerCount,
           tp.CommentCount,
           tp.PostType,
           tp.ScoreRank,
           CASE 
               WHEN tp.PostType = 'Question' AND tp.Score > 100 THEN 'Highly Voted'
               WHEN tp.PostType = 'Question' AND tp.Score > 50 THEN 'Popular'
               WHEN tp.PostType = 'Question' AND tp.Score > 10 THEN 'Moderate'
               ELSE 'Low'
           END AS ScoreCategory,
           COALESCE(
               (SELECT STRING_AGG(tag, ', ')
                FROM UNNEST(SPLIT(tp.Title, ' ')) AS tag
                WHERE LENGTH(tag) > 3 AND tag NOT LIKE '%<%' AND tag NOT LIKE '%>%'
               ), 'No Tags'
           ) AS TagSummary
    FROM TopPosts tp
    WHERE tp.ScoreRank <= 10
),
UserActivitySummary AS (
    SELECT ru.UserId,
           ru.DisplayName,
           ru.Reputation,
           ru.PostCount,
           ru.CommentCount,
           ru.BadgeCount,
           ru.RankByScore,
           ru.RankByReputation,
           ru.RankByTier,
           CASE 
               WHEN ru.PostCount > 100 THEN ' prolific'
               WHEN ru.PostCount > 50 THEN ' active'
               WHEN ru.PostCount > 10 THEN ' engaged'
               ELSE ' casual'
           END AS ActivityLevel
    FROM RankedUsers ru
    WHERE ru.PostCount > 0
),
ComplexStats AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.RankByScore,
        uas.RankByReputation,
        uas.RankByTier,
        uas.ActivityLevel,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 1 AND p.Score >= 100
        ) AS HighScoreQuestions,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 2 AND p.Score >= 50
        ) AS HighScoreAnswers,
        (
            SELECT AVG(p.Score)
            FROM Posts p
            WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 1
        ) AS AvgQuestionScore,
        (
            SELECT AVG(p.Score)
            FROM Posts p
            WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 2
        ) AS AvgAnswerScore,
        COALESCE(
            (SELECT COUNT(ps.Id) 
             FROM PostHistory ps 
             WHERE ps.UserId = uas.UserId AND ps.PostHistoryTypeId = 2), 0
        ) AS EditCount,
        COALESCE(
            (SELECT COUNT(v.Id) 
             FROM Votes v 
             WHERE v.UserId = uas.UserId AND v.VoteTypeId IN (2, 3) AND v.PostId IN (
                 SELECT p.Id FROM Posts p WHERE p.OwnerUserId = uas.UserId
             )),
             0
        ) AS VoteCount,
        CASE 
            WHEN uas.Reputation >= 10000 AND uas.PostCount > 100 THEN 'Elite Contributor'
            WHEN uas.Reputation >= 1000 AND uas.PostCount > 50 THEN 'Veteran Contributor'
            WHEN uas.Reputation >= 100 AND uas.PostCount > 10 THEN 'Regular Contributor'
            ELSE 'Contributor'
        END AS ContributorStatus
    FROM UserActivitySummary uas
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.PostCount,
    cs.CommentCount,
    cs.BadgeCount,
    cs.RankByScore,
    cs.RankByReputation,
    cs.RankByTier,
    cs.ActivityLevel,
    cs.HighScoreQuestions,
    cs.HighScoreAnswers,
    ROUND(COALESCE(cs.AvgQuestionScore, 0), 2) AS AvgQuestionScore,
    ROUND(COALESCE(cs.AvgAnswerScore, 0), 2) AS AvgAnswerScore,
    cs.EditCount,
    cs.VoteCount,
    cs.ContributorStatus,
    (
        SELECT STRING_AGG(
            CONCAT('Q', tp.PostId, ': ', tp.Title, ' (', tp.Score, ')'), 
            '; '
        )
        FROM TopPosts tp
        WHERE tp.OwnerUserId = cs.UserId AND tp.ScoreRank <= 5
        ORDER BY tp.Score DESC
    ) AS TopQuestions,
    (
        SELECT STRING_AGG(
            CONCAT('A', tp.PostId, ': ', tp.Title, ' (', tp.Score, ')'), 
            '; '
        )
        FROM TopPosts tp
        WHERE tp.OwnerUserId = cs.UserId AND tp.ScoreRank <= 5 AND tp.PostType = 'Answer'
        ORDER BY tp.Score DESC
    ) AS TopAnswers,
    (
        SELECT STRING_AGG(
            CONCAT('B', b.Id, ': ', b.Name, ' (', b.Date, ')'), 
            '; '
        )
        FROM Badges b
        WHERE b.UserId = cs.UserId
        ORDER BY b.Date DESC
        LIMIT 5
    ) AS RecentBadges,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p 
            WHERE p.OwnerUserId = cs.UserId AND p.ClosedDate IS NOT NULL
        ) THEN 'Has Closed Posts'
        ELSE 'No Closed Posts'
    END AS HasClosedPosts,
    COALESCE(
        (SELECT MAX(pp.Score) 
         FROM Posts pp 
         WHERE pp.OwnerUserId = cs.UserId AND pp.AnswerCount IS NOT NULL
        ), 0
    ) AS MaxAnswerCount,
    CASE 
        WHEN cs.Reputation > 1000 AND cs.VoteCount > 100 THEN 'Active Voter'
        WHEN cs.Reputation > 100 AND cs.VoteCount > 50 THEN 'Regular Voter'
        ELSE 'Occasional Voter'
    END AS VotingPattern,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.ParentId IS NOT NULL AND p.OwnerUserId = cs.UserId AND p.Score > 0
    ) AS AnsweredQuestionsCount,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId = 1 AND p.OwnerUserId = cs.UserId AND p.CommentCount > 0
    ) AS QuestionsWithComments,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId = 2 AND p.OwnerUserId = cs.UserId AND p.CommentCount > 0
    ) AS AnswerWithComments,
    (
        SELECT STRING_AGG(
            CONCAT('Tag: ', t.TagName, ' (', t.Count, ')'), 
            ' | '
        )
        FROM Tags t
        WHERE t.TagName ILIKE '%' || cs.DisplayName || '%'
        OR t.TagName = 'sql'
        ORDER BY t.Count DESC
        LIMIT 5
    ) AS RelevantTags
FROM ComplexStats cs
WHERE cs.PostCount > 5
AND cs.Reputation >= 100
AND (
    cs.HighScoreQuestions > 0
    OR cs.HighScoreAnswers > 0
    OR cs.EditCount > 10
    OR cs.VoteCount > 20
)
ORDER BY cs.Reputation DESC, cs.PostCount DESC
LIMIT 20;