-- {"query": "7381.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3838} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(b.Date) AS LastBadgeDate,
        MAX(v.CreationDate) AS LastVoteDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate))
            ELSE NULL 
        END AS DaysSinceLastPost,
        CASE 
            WHEN COUNT(DISTINCT c.Id) > 0 THEN 
                DATEDIFF(CURRENT_TIMESTAMP, MAX(c.CreationDate))
            ELSE NULL 
        END AS DaysSinceLastComment,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        RANK() OVER (ORDER BY u.Views DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY u.UpVotes - u.DownVotes DESC) AS NetVoteRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.LastEditDate,
        p.AcceptedAnswerId,
        p.FavoriteCount,
        p.ClosedDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END AS PostTypeName,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 THEN 'Open'
            ELSE 'N/A'
        END AS QuestionStatus,
        CASE 
            WHEN p.PostTypeId = 1 AND (p.Tags IS NOT NULL AND p.Tags != '') THEN 
                REGEXP_REPLACE(p.Tags, '<', '', 'g')
            ELSE NULL 
        END AS TagList,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND OwnerUserId IS NOT NULL)
            ELSE 0 
        END AS AnswerCountAdjusted,
        CASE 
            WHEN p.PostTypeId = 1 THEN
                (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3))
            ELSE NULL 
        END AS VoteCountAdjusted,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate)
            ELSE NULL 
        END AS DaysSinceCreation
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
DetailedUserActivity AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.VoteCount,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.LastBadgeDate,
        ua.LastVoteDate,
        ua.DaysSinceLastPost,
        ua.DaysSinceLastComment,
        ua.RepRank,
        ua.PostRank,
        ua.ViewRank,
        ua.NetVoteRank,
        COALESCE(ua.PostCount, 0) + COALESCE(ua.CommentCount, 0) AS TotalActivity,
        CASE 
            WHEN ua.BadgeCount > 0 THEN 
                (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 1)
            ELSE 0 
        END AS GoldBadgeCount,
        CASE 
            WHEN ua.BadgeCount > 0 THEN 
                (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 2)
            ELSE 0 
        END AS SilverBadgeCount,
        CASE 
            WHEN ua.BadgeCount > 0 THEN 
                (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 3)
            ELSE 0 
        END AS BronzeBadgeCount,
        CASE 
            WHEN ua.VoteCount > 0 THEN 
                (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = 2)
            ELSE 0 
        END AS UpvoteCount,
        CASE 
            WHEN ua.VoteCount > 0 THEN 
                (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = 3)
            ELSE 0 
        END AS DownvoteCount,
        CASE 
            WHEN ua.VoteCount > 0 THEN 
                ROUND((SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = 2) * 100.0 / 
                     (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId), 2)
            ELSE 0 
        END AS UpvotePercentage,
        CASE 
            WHEN ua.ViewRank = 1 THEN 'Top Viewer'
            ELSE 'Regular User'
        END AS UserCategory,
        CASE 
            WHEN ua.PostCount >= 100 THEN 'Veteran Poster'
            WHEN ua.PostCount >= 50 THEN 'Experienced Poster'
            WHEN ua.PostCount >= 10 THEN 'Active Poster'
            ELSE 'Casual Poster'
        END AS PosterCategory,
        CASE 
            WHEN ua.RepRank <= 100 THEN 'Top 100 Rep'
            WHEN ua.RepRank <= 1000 THEN 'Top 1k Rep'
            ELSE 'Regular Rep'
        END AS RepCategory
    FROM UserActivity ua
),
AggregatePostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.PostTypeName,
        ps.QuestionStatus,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.LastEditDate,
        ps.AcceptedAnswerId,
        ps.FavoriteCount,
        ps.ClosedDate,
        ps.TagList,
        ps.AnswerCountAdjusted,
        ps.VoteCountAdjusted,
        ps.DaysSinceCreation,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY ps.ViewCount DESC) AS ViewRank,
        DENSE_RANK() OVER (ORDER BY ps.CommentCount DESC) AS CommentRank,
        DENSE_RANK() OVER (ORDER BY ps.AnswerCountAdjusted DESC) AS AnswerRank,
        DENSE_RANK() OVER (ORDER BY ps.FavoriteCount DESC) AS FavoriteRank,
        CASE 
            WHEN ps.Score >= 100 THEN 'High Impact'
            WHEN ps.Score >= 50 THEN 'Medium Impact'
            WHEN ps.Score >= 10 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END AS ImpactCategory,
        CASE 
            WHEN ps.ViewCount > 1000 THEN 'Viral'
            WHEN ps.ViewCount > 500 THEN 'Popular'
            WHEN ps.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low Exposure'
        END AS ExposureCategory,
        CASE 
            WHEN ps.AnswerCountAdjusted > 10 THEN 'Highly Answered'
            WHEN ps.AnswerCountAdjusted > 5 THEN 'Moderately Answered'
            ELSE 'Lowly Answered'
        END AS AnswerCategory,
        CASE 
            WHEN ps.CommentCount > 20 THEN 'Highly Commented'
            WHEN ps.CommentCount > 10 THEN 'Moderately Commented'
            ELSE 'Lowly Commented'
        END AS CommentCategory,
        CASE 
            WHEN ps.DaysSinceCreation < 7 AND ps.Score >= 50 THEN 'Hot Recent'
            WHEN ps.DaysSinceCreation < 30 AND ps.Score >= 25 THEN 'Recent Trending'
            WHEN ps.Score >= 100 THEN 'Classic High'
            ELSE 'Normal'
        END AS TemporalCategory
    FROM PostStats ps
),
CombinedAnalysis AS (
    SELECT 
        dua.UserId,
        dua.DisplayName,
        dua.Reputation,
        dua.Views,
        dua.UpVotes,
        dua.DownVotes,
        dua.PostCount,
        dua.CommentCount,
        dua.BadgeCount,
        dua.VoteCount,
        dua.LastPostDate,
        dua.LastCommentDate,
        dua.LastBadgeDate,
        dua.LastVoteDate,
        dua.DaysSinceLastPost,
        dua.DaysSinceLastComment,
        dua.RepRank,
        dua.PostRank,
        dua.ViewRank,
        dua.NetVoteRank,
        dua.TotalActivity,
        dua.GoldBadgeCount,
        dua.SilverBadgeCount,
        dua.BronzeBadgeCount,
        dua.UpvoteCount,
        dua.DownvoteCount,
        dua.UpvotePercentage,
        dua.UserCategory,
        dua.PosterCategory,
        dua.RepCategory,
        apa.ScoreRank,
        apa.ViewRank AS PostViewRank,
        apa.CommentRank,
        apa.AnswerRank,
        apa.FavoriteRank,
        apa.ImpactCategory,
        apa.ExposureCategory,
        apa.AnswerCategory,
        apa.CommentCategory,
        apa.TemporalCategory,
        apa.PostTypeId,
        apa.PostTypeName,
        apa.QuestionStatus,
        apa.Title,
        apa.Tags,
        apa.Score,
        apa.ViewCount,
        apa.AnswerCount,
        apa.CommentCount,
        apa.CreationDate,
        apa.LastActivityDate,
        apa.LastEditDate,
        apa.AcceptedAnswerId,
        apa.FavoriteCount,
        apa.ClosedDate,
        apa.TagList,
        apa.AnswerCountAdjusted,
        apa.VoteCountAdjusted,
        apa.DaysSinceCreation,
        CASE 
            WHEN dua.BadgeCount > 0 AND dua.RepRank = 1 THEN 'Top Achiever'
            WHEN dua.BadgeCount > 0 AND dua.RepRank <= 10 THEN 'Notable Achiever'
            WHEN dua.BadgeCount = 0 THEN 'InActive'
            ELSE 'Regular Achiever'
        END AS AchievementLevel,
        CASE 
            WHEN dua.PostCount > 100 THEN 1
            WHEN dua.PostCount > 50 THEN 2
            WHEN dua.PostCount > 20 THEN 3
            ELSE 4
        END AS PostingLevel,
        CASE 
            WHEN dua.Reputation > 10000 THEN 1
            WHEN dua.Reputation > 5000 THEN 2
            WHEN dua.Reputation > 1000 THEN 3
            ELSE 4
        END AS ReputationLevel
    FROM DetailedUserActivity dua
    FULL OUTER JOIN AggregatePostAnalysis apa ON dua.UserId = apa.OwnerUserId
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.Views,
    ca.UpVotes,
    ca.DownVotes,
    ca.PostCount,
    ca.CommentCount,
    ca.BadgeCount,
    ca.VoteCount,
    ca.LastPostDate,
    ca.LastCommentDate,
    ca.LastBadgeDate,
    ca.LastVoteDate,
    ca.DaysSinceLastPost,
    ca.DaysSinceLastComment,
    ca.RepRank,
    ca.PostRank,
    ca.ViewRank,
    ca.NetVoteRank,
    ca.TotalActivity,
    ca.GoldBadgeCount,
    ca.SilverBadgeCount,
    ca.BronzeBadgeCount,
    ca.UpvoteCount,
    ca.DownvoteCount,
    ca.UpvotePercentage,
    ca.UserCategory,
    ca.PosterCategory,
    ca.RepCategory,
    ca.ScoreRank,
    ca.PostViewRank,
    ca.CommentRank,
    ca.AnswerRank,
    ca.FavoriteRank,
    ca.ImpactCategory,
    ca.ExposureCategory,
    ca.AnswerCategory,
    ca.CommentCategory,
    ca.TemporalCategory,
    ca.PostTypeId,
    ca.PostTypeName,
    ca.QuestionStatus,
    ca.Title,
    ca.Tags,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.CreationDate,
    ca.LastActivityDate,
    ca.LastEditDate,
    ca.AcceptedAnswerId,
    ca.FavoriteCount,
    ca.ClosedDate,
    ca.TagList,
    ca.AnswerCountAdjusted,
    ca.VoteCountAdjusted,
    ca.DaysSinceCreation,
    ca.AchievementLevel,
    ca.PostingLevel,
    ca.ReputationLevel,
    CASE 
        WHEN ca.Score > 100 AND ca.ViewCount > 500 THEN 'High-Impact Post'
        WHEN ca.Score > 50 AND ca.ViewCount > 200 THEN 'Moderate-Impact Post'
        WHEN ca.Score IS NULL OR ca.ViewCount IS NULL THEN 'No Post Data'
        ELSE 'Low-Impact Post'
    END AS PostImpact,
    CASE 
        WHEN ca.ViewCount IS NOT NULL AND ca.ViewCount >= 1000 THEN 'Viral Post'
        WHEN ca.ViewCount IS NOT NULL AND ca.ViewCount >= 500 THEN 'Popular Post'
        WHEN ca.ViewCount IS NOT NULL AND ca.ViewCount >= 100 THEN 'Moderate Post'
        ELSE 'Low Activity Post'
    END AS PostPopularity,
    CASE 
        WHEN ca.Score IS NOT NULL AND ca.Score > 50 THEN 'Upvoted Post'
        WHEN ca.Score IS NOT NULL AND ca.Score < -10 THEN 'Downvoted Post'
        ELSE 'Neutral Post'
    END AS PostSentiment,
    CASE 
        WHEN ca.PostCount IS NOT NULL AND ca.PostCount >= 100 THEN 'Veteran User'
        WHEN ca.PostCount IS NOT NULL AND ca.PostCount >= 50 THEN 'Experienced User'
        WHEN ca.PostCount IS NOT NULL AND ca.PostCount >= 10 THEN 'Active User'
        ELSE 'Passive User'
    END AS UserActivityLevel,
    CASE 
        WHEN ca.BadgeCount IS NOT NULL AND ca.BadgeCount = 0 THEN 'No Achievements'
        WHEN ca.BadgeCount IS NOT NULL AND ca.BadgeCount > 0 AND ca.BadgeCount < 5 THEN 'Some Achievements'
        WHEN ca.BadgeCount IS NOT NULL AND ca.BadgeCount >= 5 THEN 'Multiple Achievements'
        ELSE 'Unknown'
    END AS AchievementStatus,
    CASE 
        WHEN ca.UpvoteCount IS NOT NULL AND ca.DownvoteCount IS NOT NULL THEN 
            CASE 
                WHEN ca.UpvoteCount > ca.DownvoteCount THEN 'More Upvotes'
                WHEN ca.UpvoteCount < ca.DownvoteCount THEN 'More Downvotes'
                ELSE 'Equal Votes'
            END
        ELSE 'No Votes'
    END AS VoteDistribution,
    CASE 
        WHEN EXISTS(
            SELECT 1 FROM PostLinks pl WHERE pl.PostId = ca.PostId AND pl.LinkTypeId = 1
        ) THEN 'Has Links'
        WHEN EXISTS(
            SELECT 1 FROM PostLinks pl WHERE pl.PostId = ca.PostId AND pl.LinkTypeId = 3
        ) THEN 'Is Duplicate'
        ELSE 'No Links'
    END AS LinkStatus,
    CASE 
        WHEN ca.PostTypeId = 1 AND ca.QuestionStatus = 'Closed' THEN 'Closed Question'
        WHEN ca.PostTypeId = 1 AND ca.QuestionStatus = 'Answered' THEN 'Answered Question'
        WHEN ca.PostTypeId = 1 AND ca.QuestionStatus = 'Open' THEN 'Open Question'
        ELSE 'Non-Question'
    END AS QuestionStatusDetail,
    ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC, ca.PostCount DESC) AS OverallRank,
    COUNT(*) OVER () AS TotalRecords,
    CASE 
        WHEN ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC) <= 10 THEN 'Top 10'
        WHEN ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC) <= 100 THEN 'Top 100'
        WHEN ROW_NUMBER() OVER (ORDER BY ca.Reputation DESC) <= 1000 THEN 'Top 1K'
        ELSE 'Rest of Users'
    END AS TopTier,
    CASE 
        WHEN ca.RepRank <= 1 THEN 'Founder'
        WHEN ca.RepRank <= 10 THEN 'Elite'
        WHEN ca.RepRank <= 100 THEN 'High Rank'
        WHEN ca.RepRank <= 1000 THEN 'Mid Rank'
        ELSE 'Lower Rank'
    END AS RankTier
FROM CombinedAnalysis ca
WHERE ca.UserId IS NOT NULL AND (ca.PostTypeId IS NOT NULL OR ca.UserId IN (SELECT Id FROM Users WHERE Reputation > 0))
ORDER BY ca.Reputation DESC, ca.PostCount DESC, ca.ViewCount DESC, ca.Score DESC
LIMIT 1000 OFFSET 0;