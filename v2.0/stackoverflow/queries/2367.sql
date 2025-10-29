WITH RecursiveRecentBadges AS (
    SELECT 
        b.Id,
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        u.DisplayName,
        dense_rank() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b 
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Date > CAST('2024-10-01' AS date) - INTERVAL '1 year'
),
TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COALESCE(rrb.badges_count, 0) AS RecentBadgeCount,
        COALESCE(q.AvgQuestionScore, 0) AS AvgQuestionScore,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS badges_count
        FROM RecursiveRecentBadges
        WHERE BadgeRank <= 5
        GROUP BY UserId
    ) rrb ON u.Id = rrb.UserId
    LEFT JOIN (
        SELECT OwnerUserId, AVG(Score) AS AvgQuestionScore
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) q ON u.Id = q.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId, AVG(Score) AS AvgAnswerScore
        FROM Posts 
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) a ON u.Id = a.OwnerUserId
    WHERE u.Reputation > 1000
),
QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn,
        COALESCE(pl.LinkCnt, 0) AS LinkedPostsCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS LinkCnt
        FROM PostLinks
        WHERE LinkTypeId = 1
        GROUP BY PostId
    ) pl ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '2 years'
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.Tags, pl.LinkCnt
),
TopQuestions AS (
    SELECT *
    FROM QuestionStats
    WHERE rn <= 3
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(pq.QuestionCount, 0) AS QuestionsPosted,
        COALESCE(pa.AnswerCount, 0) AS AnswersPosted,
        COALESCE(cmt.CommentCount, 0) AS CommentsMade,
        COALESCE(vt.VotesCast, 0) AS VotesCast,
        COALESCE(gold.GoldBadges, 0) AS GoldBadges,
        COALESCE(silver.SilverBadges, 0) AS SilverBadges,
        COALESCE(bronze.BronzeBadges, 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount
        FROM Posts 
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) pq ON u.Id = pq.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts 
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) pa ON u.Id = pa.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY UserId
    ) cmt ON u.Id = cmt.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS VotesCast
        FROM Votes
        GROUP BY UserId
    ) vt ON u.Id = vt.UserId
    LEFT JOIN (
        SELECT b1.UserId, COUNT(DISTINCT b1.Id) AS GoldBadges
        FROM Badges b1
        WHERE b1.Class = 1
        GROUP BY b1.UserId
    ) gold ON u.Id = gold.UserId
    LEFT JOIN (
        SELECT b2.UserId, COUNT(DISTINCT b2.Id) AS SilverBadges
        FROM Badges b2
        WHERE b2.Class = 2
        GROUP BY b2.UserId
    ) silver ON u.Id = silver.UserId
    LEFT JOIN (
        SELECT b3.UserId, COUNT(DISTINCT b3.Id) AS BronzeBadges
        FROM Badges b3
        WHERE b3.Class = 3
        GROUP BY b3.UserId
    ) bronze ON u.Id = bronze.UserId
),
DuplicateLinks AS (
    SELECT pl.PostId, pl.RelatedPostId, p.Title AS OriginalTitle, rp.Title AS DuplicateTitle
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts rp ON pl.RelatedPostId = rp.Id
    WHERE pl.LinkTypeId = 3
),
RecentEditsCTE AS (
    SELECT 
        ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.UserDisplayName,
        row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '90 days'
),
LatestEdits AS (
    SELECT PostId, PostHistoryTypeId, CreationDate, UserId, UserDisplayName
    FROM RecentEditsCTE
    WHERE rn = 1
),
CompositeResults AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.RecentBadgeCount,
        qs.QuestionId,
        qs.Title AS QuestionTitle,
        qs.Score AS QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.VotesCast,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        le.CreationDate AS LastEditDate,
        le.UserDisplayName AS LastEditor,
        dup.OriginalTitle AS DuplicateOriginalQuestion,
        dup.DuplicateTitle AS DuplicateLinkedQuestion,
        substring(qs.Tags FROM '<([^<>]+)>') AS FirstTag,
        CASE WHEN qs.ViewCount > 0 THEN round(CAST(qs.Score AS numeric) / qs.ViewCount, 4) ELSE NULL END AS ScorePerView,
        CASE 
            WHEN ua.GoldBadges > 0 THEN 'Gold Contributor'
            WHEN ua.SilverBadges > 5 THEN 'Silver Contributor'
            WHEN ua.BronzeBadges > 10 THEN 'Bronze Contributor'
            ELSE 'New Contributor'
        END AS ContributorLevel,
        rank() OVER (
            PARTITION BY
                CASE 
                    WHEN ua.GoldBadges > 0 THEN 'Gold Contributor'
                    WHEN ua.SilverBadges > 5 THEN 'Silver Contributor'
                    WHEN ua.BronzeBadges > 10 THEN 'Bronze Contributor'
                    ELSE 'New Contributor'
                END
            ORDER BY u.Reputation DESC
        ) AS ReputationRank
    FROM TopUsers u
    LEFT JOIN TopQuestions qs ON u.Id = qs.OwnerUserId
    LEFT JOIN UserActivity ua ON ua.UserId = u.Id
    LEFT JOIN LatestEdits le ON le.PostId = qs.QuestionId
    LEFT JOIN DuplicateLinks dup ON dup.PostId = qs.QuestionId
)
SELECT *
FROM CompositeResults
WHERE (ContributorLevel = 'Gold Contributor' AND ReputationRank <= 5)
   OR (ContributorLevel = 'Silver Contributor' AND ReputationRank <= 3)
ORDER BY ContributorLevel DESC, ReputationRank, QuestionScore DESC;