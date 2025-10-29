-- {"query": "7436.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3836} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END as PostType,
    COALESCE(p.Tags, '') as Tags,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    COALESCE(p.CommentCount, 0) as CommentCount,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(DAY, p.CreationDate, p.ClosedDate)
        ELSE NULL 
    END as DaysToClose,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId = p.Id 
        AND c.CreationDate > DATEADD(MONTH, -1, GETDATE())
    ) as RecentComments,
    (
        SELECT TOP 1 ph.Text 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (1, 4) 
        AND ph.CreationDate = (
            SELECT MAX(ph2.CreationDate) 
            FROM PostHistory ph2 
            WHERE ph2.PostId = p.Id 
            AND ph2.PostHistoryTypeId IN (1, 4)
        )
    ) as LatestTitle,
    (
        SELECT STRING_AGG(b.Name, ', ') 
        FROM Badges b 
        WHERE b.UserId = p.OwnerUserId 
        AND b.Date > DATEADD(YEAR, -1, GETDATE())
    ) as RecentBadges,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
    RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
    NTILE(100) OVER (ORDER BY p.Score) as ScorePercentile,
    LAG(p.ViewCount, 1) OVER (ORDER BY p.CreationDate) as PreviousViewCount,
    LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
    SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS UNBOUNDED PRECEDING) as CumulativeViews,
    COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsPerUser,
    CASE 
        WHEN p.AnswerCount > 0 AND p.Score >= 10 THEN 'HighValue'
        WHEN p.Score < 0 THEN 'Negative'
        WHEN p.Score BETWEEN 0 AND 10 THEN 'Neutral'
        ELSE 'Positive'
    END as ScoreCategory,
    COALESCE(
        (
            SELECT TOP 1 v.VoteTypeId 
            FROM Votes v 
            WHERE v.PostId = p.Id 
            AND v.UserId = p.OwnerUserId
        ), 0
    ) as OwnerVoteType,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id 
        AND v.VoteTypeId IN (2, 3) /* Upvote/Downvote */
    ) as NetVotes,
    EXISTS(
        SELECT 1 
        FROM Posts p2 
        WHERE p2.ParentId = p.Id 
        AND p2.PostTypeId = 2 
        AND p2.Score > 10
    ) as HasHighScoringAnswer,
    (
        SELECT COUNT(DISTINCT ph.UserId) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.UserId IS NOT NULL
    ) as EditorCount,
    CASE 
        WHEN p.Tags LIKE '%<%<%' AND p.Tags LIKE '%>%>%' THEN 'MultipleTags'
        ELSE 'SingleTag'
    END as TagStructure,
    CAST(
        DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS FLOAT
    ) / 86400.0 as DaysSinceActivity,
    CASE 
        WHEN EXISTS(
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.PostId = p.Id 
            AND pl.LinkTypeId = 1
        ) THEN 'Linked'
        ELSE 'NotLinked'
    END as LinkStatus,
    (
        SELECT COALESCE(SUM(v.BountyAmount), 0)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 8 /* BountyStart */
    ) as TotalBounty,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = p.OwnerUserId 
        AND b.Class = 1
    ) as GoldBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = p.OwnerUserId 
        AND b.Class = 2
    ) as SilverBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = p.OwnerUserId 
        AND b.Class = 3
    ) as BronzeBadgeCount,
    CASE 
        WHEN p.FavoriteCount > 0 THEN (CAST(p.FavoriteCount AS FLOAT) / NULLIF(p.ViewCount, 0)) * 100
        ELSE 0
    END as BookmarkRate,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId = p.Id 
        AND c.Text LIKE '%help%'
    ) as HelpMentions,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (2, 5) /* Edit Body */
    ) as BodyEdits,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (3, 6) /* Edit Tags */
    ) as TagEdits,
    (
        SELECT TOP 1 ph.CreationDate 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 10 /* Post Closed */
        ORDER BY ph.CreationDate ASC
    ) as FirstCloseDate,
    (
        SELECT TOP 1 ph.CreationDate 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 11 /* Post Reopened */
        ORDER BY ph.CreationDate ASC
    ) as FirstReopenDate,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 13 /* Post Undeleted */
    ) as UndeleteCount,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (12, 10, 11) /* Deleted, Closed, Reopened */
    ) as ActivityCount,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN ph.PostHistoryTypeId IN (10, 11) THEN 'StatusChange'
                WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'BodyEdit'
                WHEN ph.PostHistoryTypeId IN (3, 6) THEN 'TagEdit'
                ELSE 'Other'
            END, 
            ', '
        ) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id
    ) as RecentActivityTypes,
    (
        SELECT MAX(ph.CreationDate) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.UserId = p.OwnerUserId
    ) as OwnerLastEditDate,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id 
        AND v.UserId = p.OwnerUserId
        AND v.VoteTypeId = 5 /* Favorite */
    ) as OwnerFavorites,
    (
        SELECT COUNT(DISTINCT v.UserId) 
        FROM Votes v 
        WHERE v.PostId = p.Id 
        AND v.VoteTypeId IN (2, 3, 5)
    ) as UniqueVoters,
    (
        SELECT AVG(p2.ViewCount) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = p.OwnerUserId 
        AND p2.Id != p.Id
    ) as AvgViewsForUser,
    ABS(p.ViewCount - (
        SELECT AVG(p2.ViewCount) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = p.OwnerUserId 
        AND p2.Id != p.Id
    )) as ViewCountDeviation,
    CASE 
        WHEN p.ViewCount >= (
            SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p2.ViewCount) 
            FROM Posts p2 
            WHERE p2.OwnerUserId = p.OwnerUserId
        ) THEN 'Top5Percent'
        WHEN p.ViewCount >= (
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p2.ViewCount) 
            FROM Posts p2 
            WHERE p2.OwnerUserId = p.OwnerUserId
        ) THEN 'Median'
        ELSE 'BelowMedian'
    END as ViewPercentileCategory,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.CreationDate > DATEADD(WEEK, -2, GETDATE())
    ) as RecentActivityCount,
    (
        SELECT AVG(ph.CreationDate) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id
    ) as AvgActivityDate,
    (
        SELECT MAX(ph.CreationDate) - MIN(ph.CreationDate) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id
    ) as ActivityDuration,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.Comment IS NOT NULL
    ) as CommentedEvents,
    (
        SELECT TOP 1 ph.Comment 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.Comment IS NOT NULL
        ORDER BY ph.CreationDate DESC
    ) as LastEventComment,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN p3.PostTypeId = 1 THEN 'Q'
                WHEN p3.PostTypeId = 2 THEN 'A'
                ELSE 'O'
            END, 
            '-'
        ) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = p.OwnerUserId 
        AND p3.Id != p.Id
        ORDER BY p3.CreationDate DESC
    ) as UserPostTypeSequence,
    (
        SELECT COUNT(*) 
        FROM Posts p4 
        WHERE p4.OwnerUserId = p.OwnerUserId 
        AND p4.CreationDate > DATEADD(MONTH, -3, GETDATE())
    ) as RecentPostsCount,
    (
        SELECT STRING_AGG(
            LEFT(p5.Title, 20) + ' [' + 
            CASE WHEN p5.Score >= 10 THEN 'High' ELSE 'Low' END + ']',
            ' | '
        ) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = p.OwnerUserId 
        AND p5.Id != p.Id
        ORDER BY p5.Score DESC
        OFFSET 0 ROWS
        FETCH NEXT 3 ROWS ONLY
    ) as TopPostsByScore,
    (
        SELECT STRING_AGG(
            c.Text, 
            ' | '
        ) 
        FROM Comments c 
        WHERE c.PostId = p.Id
        AND LEN(c.Text) > 50
        ORDER BY c.CreationDate DESC
        OFFSET 0 ROWS
        FETCH NEXT 2 ROWS ONLY
    ) as LongComments,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    ) as TotalEdits,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 24 /* Suggested Edit Applied */
    ) as SuggestedEdits,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 17 /* Post Migrated */
    ) as MigrationEvents,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (19, 20) /* Protected/Unprotected */
    ) as ProtectionEvents,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 35 /* Migrated Away */
    ) as MigratedAway,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId = 36 /* Migrated Here */
    ) as MigratedHere,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (33, 34) /* Notice Added/Removed */
    ) as NoticeEvents,
    (
        SELECT COALESCE(MAX(ph.CreationDate), p.CreationDate)
        FROM PostHistory ph 
        WHERE ph.PostId = p.Id
    ) as LastModificationDate,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId = p.Id
    ) as DirectLinks,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.RelatedPostId = p.Id
    ) as IncomingLinks,
    (
        SELECT COUNT(*) 
        FROM Tags t 
        WHERE t.TagName IN (
            SELECT value 
            FROM STRING_SPLIT(
                NULLIF(NULLIF(NULLIF(p.Tags, ''), ' '), '')
                , '><'
            )
        )
    ) as TagMatches,
    (
        SELECT COUNT(*) 
        FROM Users u2 
        WHERE u2.AccountId = u.AccountId
    ) as AccountUserCount,
    (
        SELECT STRING_AGG(
            CONCAT('U', u2.Id, '-', u2.Reputation),
            ' | '
        ) 
        FROM Users u2 
        WHERE u2.AccountId = u.AccountId
        AND u2.Id != u.Id
        ORDER BY u2.Reputation DESC
        OFFSET 0 ROWS
        FETCH NEXT 2 ROWS ONLY
    ) as OtherAccountIdUsers,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id
    ) as TotalBadges,
    (
        SELECT STRING_AGG(
            b.Name,
            ', '
        ) WITHIN GROUP (ORDER BY b.Date DESC)
        FROM Badges b 
        WHERE b.UserId = u.Id
        AND b.Date > DATEADD(YEAR, -2, GETDATE())
    ) as RecentBadgesList,
    (
        SELECT STRING_AGG(
            'V' + CAST(v.VoteTypeId AS VARCHAR(2)) + ' ' +
            CASE WHEN v.VoteTypeId IN (2, 3) THEN CAST(v.BountyAmount AS VARCHAR(10)) ELSE '' END,
            ' | '
        )
        FROM Votes v 
        WHERE v.UserId = u.Id
        ORDER BY v.CreationDate DESC
        OFFSET 0 ROWS
        FETCH NEXT 3 ROWS ONLY
    ) as RecentVotes,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.PostTypeId = 2 /* Answer */
    ) as AnswerCount,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.PostTypeId = 1 /* Question */
    ) as QuestionCount,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.PostTypeId = 3 /* Wiki */
    ) as WikiCount,
    (
        SELECT AVG(p7.ViewCount) 
        FROM Posts p7 
        WHERE p7.OwnerUserId = u.Id
    ) as AvgPostViews,
    (
        SELECT SUM(p7.Score) 
        FROM Posts p7 
        WHERE p7.OwnerUserId = u.Id
    ) as TotalScore
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE (
    p.PostTypeId IN (1, 2) 
    AND p.ViewCount >= 100
    AND (
        p.Score > 5 
        OR p.AnswerCount > 3
        OR p.FavoriteCount > 2
    )
)
AND (
    p.CreationDate >= DATEADD(MONTH, -6, GETDATE())
    OR p.LastActivityDate >= DATEADD(MONTH, -6, GETDATE())
)
AND NOT EXISTS (
    SELECT 1 
    FROM PostHistory ph 
    WHERE ph.PostId = p.Id 
    AND ph.PostHistoryTypeId = 12 /* Post Deleted */
)
AND (
    u.Id IS NOT NULL 
    OR p.OwnerUserId = -1 /* Community wiki */
)
AND (
    p.Tags IS NOT NULL 
    AND LEN(TRIM(p.Tags)) > 0
)
AND (
    p.Title IS NOT NULL 
    AND LEN(TRIM(p.Title)) > 10
)
AND (
    p.Body IS NOT NULL 
    AND LEN(TRIM(p.Body)) > 50
)
AND (
    (p.PostTypeId = 1 AND p.AnswerCount IS NOT NULL)
    OR (p.PostTypeId = 2 AND p.ParentId IS NOT NULL)
)
ORDER BY p.Score DESC, p.ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY
OPTION (MAXDOP 4)