-- {"query": "7322.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3246} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        p.ParentId,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) AS DaysActive,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END AS VoteCategory,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 5000 THEN 'Popular'
            WHEN p.ViewCount > 1000 THEN 'Noticeable'
            WHEN p.ViewCount > 0 THEN 'Obscure'
            ELSE 'Unseen'
        END AS ViewCategory,
        TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')) AS CleanedTags,
        STRING_TO_ARRAY(TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')), '><') AS TagArray,
        LENGTH(p.Body) AS BodyLength,
        COUNT(c.Id) AS CommentCountActual,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankByType,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS OverallRank,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType,
        MAX(p.Score) OVER (PARTITION BY p.PostTypeId) AS MaxScoreByType,
        NTILE(4) OVER (ORDER BY p.Score) AS Quartile,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) AS NextScore,
        p.Score - LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) AS ScoreDeltaFromPrev,
        p.Score - LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) AS ScoreDeltaFromNext,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = p.Id 
                AND ph.PostHistoryTypeId IN (10, 11) 
                AND ph.CreationDate > p.CreationDate
            ) THEN 1
            ELSE 0
        END AS HasCloseReopenHistory,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) AS UpvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) AS DownvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM PostLinks pl 
             WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3),
            0
        ) AS DuplicateLinkCount,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph 
             WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (17, 35, 36)),
            0
        ) AS MigrationCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF('day', p.CreationDate, p.ClosedDate)
            ELSE NULL 
        END AS DaysToClose,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM Posts p2 
                WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.Score > 0
            ) THEN 1
            ELSE 0 
        END AS HasNonZeroAnswer,
        COALESCE(
            (SELECT COUNT(DISTINCT ph.UserId) 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id),
            0
        ) AS EditorsCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2) 
      AND (p.Score IS NOT NULL OR p.ViewCount IS NOT NULL OR p.AnswerCount IS NOT NULL)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.Score) AS MaxPostScore,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Newbie'
        END AS PostingLevel,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(t.Count, 0) AS FinalTagCount,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Noticeable'
            ELSE 'Niche'
        END AS TagPopularityLevel,
        t.IsModeratorOnly,
        t.IsRequired,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS PrevTagCount,
        LEAD(t.Count, 1) OVER (ORDER BY t.Count DESC) AS NextTagCount,
        t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS CountDeltaFromPrev,
        t.Count - LEAD(t.Count, 1) OVER (ORDER BY t.Count DESC) AS CountDeltaFromNext,
        NTILE(5) OVER (ORDER BY t.Count DESC) AS TagQuintile,
        AVG(t.Count) OVER () AS AvgTagCount,
        MAX(t.Count) OVER () AS MaxTagCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
RankedPosts AS (
    SELECT 
        ps.*,
        us.Reputation AS OwnerReputation,
        us.PostingLevel AS UserLevel,
        ts.TagCount AS RelatedTagCount,
        ts.TagPopularityLevel AS TagPopularity,
        CASE 
            WHEN ps.HasCloseReopenHistory = 1 AND ps.OwnerUserId IS NOT NULL THEN 'HasCloseReopenHistoryAndUser'
            WHEN ps.HasCloseReopenHistory = 1 THEN 'HasCloseReopenHistory'
            WHEN ps.OwnerUserId IS NOT NULL THEN 'HasUser'
            ELSE 'NoMetadata'
        END AS PostMetadataStatus
    FROM PostStats ps
    LEFT JOIN UserStats us ON ps.OwnerUserId = us.UserId
    LEFT JOIN TagStats ts ON ts.TagName = (
        SELECT TRIM(BOTH '<>' FROM COALESCE(SPLIT_PART(ps.CleanedTags, '><', 1), ''))
    )
),
ScoreAnalysis AS (
    SELECT 
        *,
        CASE 
            WHEN Score > AvgScoreByType THEN 'AboveAverage'
            WHEN Score = AvgScoreByType THEN 'Average'
            WHEN Score < AvgScoreByType THEN 'BelowAverage'
            ELSE 'Unknown'
        END AS ScoreVsAverage,
        CASE 
            WHEN Score < 0 THEN 'Critical'
            WHEN Score = 0 THEN 'Neutral'
            WHEN Score BETWEEN 1 AND 50 THEN 'Low'
            WHEN Score BETWEEN 51 AND 100 THEN 'Medium'
            WHEN Score BETWEEN 101 AND 500 THEN 'High'
            ELSE 'Extreme'
        END AS ScoreSeverity,
        CASE 
            WHEN DaysActive > 30 THEN 'LongLived'
            WHEN DaysActive > 7 THEN 'MidLived'
            WHEN DaysActive > 0 THEN 'ShortLived'
            ELSE 'Newborn'
        END AS ActivityLifespan,
        CASE 
            WHEN ViewCount = 0 AND AnswerCount = 0 THEN 'Orphaned'
            WHEN ViewCount > 0 AND AnswerCount = 0 THEN 'Unanswered'
            WHEN ViewCount > 0 AND AnswerCount > 0 THEN 'Answered'
            WHEN ViewCount = 0 AND AnswerCount > 0 THEN 'Unviewed'
            ELSE 'UnknownStatus'
        END AS EngagementStatus,
        CASE 
            WHEN TagArray IS NOT NULL AND ARRAY_LENGTH(TagArray, 1) > 0 THEN 
                ARRAY_TO_STRING(
                    ARRAY(
                        SELECT TRIM(leading '<' FROM TRIM(trailing '>' FROM t))
                        FROM UNNEST(TagArray) AS t
                        WHERE t IS NOT NULL AND t NOT IN ('', '<>', '><')
                    ),
                    ', '
                )
            WHEN CleanedTags IS NOT NULL AND CleanedTags != '' THEN CleanedTags
            ELSE NULL
        END AS NormalizedTags,
        CASE 
            WHEN BodyLength > 5000 THEN 'VeryLong'
            WHEN BodyLength > 1000 THEN 'Long'
            WHEN BodyLength > 500 THEN 'Medium'
            WHEN BodyLength > 0 THEN 'Short'
            ELSE 'Empty'
        END AS BodyLengthCategory,
        CASE 
            WHEN UpvoteCount > 0 AND DownvoteCount = 0 THEN 'Upvoted'
            WHEN DownvoteCount > 0 AND UpvoteCount = 0 THEN 'Downvoted'
            WHEN UpvoteCount > DownvoteCount THEN 'UpvotedMore'
            WHEN DownvoteCount > UpvoteCount THEN 'DownvotedMore'
            WHEN UpvoteCount > 0 THEN 'BalancedUpvotes'
            WHEN DownvoteCount > 0 THEN 'BalancedDownvotes'
            ELSE 'NoVotes'
        END AS VotingBalance
    FROM RankedPosts
),
FinalAnalysis AS (
    SELECT 
        *
    FROM ScoreAnalysis
    WHERE PostId IS NOT NULL
      AND Score IS NOT NULL
      AND OwnerUserId IS NOT NULL
      AND (AnswerCount IS NULL OR AnswerCount >= 0)
      AND (CommentCount IS NULL OR CommentCount >= 0)
      AND CreationDate IS NOT NULL
      AND LastActivityDate IS NOT NULL
)

SELECT 
    fa.PostId,
    fa.PostTypeId,
    fa.PostTypeDesc,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.OwnerUserId,
    fa.Title,
    fa.CleanedTags,
    fa.NormalizedTags,
    fa.DaysActive,
    fa.VoteCategory,
    fa.ViewCategory,
    fa.PostMetadataStatus,
    fa.OwnerReputation,
    fa.UserLevel,
    fa.RelatedTagCount,
    fa.TagPopularity,
    fa.ScoreVsAverage,
    fa.ScoreSeverity,
    fa.ActivityLifespan,
    fa.EngagementStatus,
    fa.BodyLengthCategory,
    fa.VotingBalance,
    fa.UpvoteCount,
    fa.DownvoteCount,
    fa.ScoreRankByType,
    fa.OverallRank,
    fa.Quartile,
    fa.ScoreDeltaFromPrev,
    fa.ScoreDeltaFromNext,
    fa.HasCloseReopenHistory,
    fa.DaysToClose,
    fa.HasNonZeroAnswer,
    fa.EditorsCount,
    fa.MigrationCount,
    fa.DuplicateLinkCount,
    fa.AvgScoreByType,
    fa.MaxScoreByType,
    fa.BodyLength,
    fa.CommentCountActual,
    fa.ReputationRank,
    fa.ActivityLevel,
    fa.PostingLevel,
    fa.TagQuintile,
    fa.CountDeltaFromPrev,
    fa.CountDeltaFromNext
FROM FinalAnalysis fa
WHERE (fa.Score > 0 OR fa.ViewCount > 0 OR fa.AnswerCount > 0 OR fa.CommentCount > 0)
  AND (fa.OwnerUserId IS NOT NULL OR fa.OwnerDisplayName IS NOT NULL)
  AND (fa.TagArray IS NOT NULL OR fa.CleanedTags IS NOT NULL OR fa.NormalizedTags IS NOT NULL)
  AND (fa.LastActivityDate IS NOT NULL AND fa.CreationDate IS NOT NULL AND fa.LastActivityDate >= fa.CreationDate)
  AND fa.Score BETWEEN -1000 AND 10000
  AND fa.ViewCount BETWEEN 0 AND 1000000
  AND fa.AnswerCount BETWEEN 0 AND 10000
  AND fa.CommentCount BETWEEN 0 AND 10000
  AND fa.FavoriteCount BETWEEN 0 AND 50000
  AND fa.OwnerReputation BETWEEN 0 AND 10000000
  AND fa.DaysActive BETWEEN 0 AND 3650
  AND fa.BodyLength BETWEEN 0 AND 400000
  AND fa.UpvoteCount BETWEEN 0 AND 50000
  AND fa.DownvoteCount BETWEEN 0 AND 50000
  AND fa.EditorsCount BETWEEN 0 AND 5000
  AND fa.DuplicateLinkCount BETWEEN 0 AND 1000
  AND fa.MigrationCount BETWEEN 0 AND 100
  AND fa.RelatedTagCount BETWEEN 0 AND 10000
  AND fa.TagCount BETWEEN 0 AND 100000
ORDER BY 
    fa.Score DESC, 
    fa.ViewCount DESC, 
    fa.AnswerCount DESC, 
    fa.CommentCount DESC,
    fa.FavoriteCount DESC
LIMIT 10000;