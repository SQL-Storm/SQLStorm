WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostCreationDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 5 THEN 1 ELSE 0 END) AS TagWikiCount,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostId = p.Id
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId = p.Id
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.PostId = p.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN CAST((EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400) AS INTEGER)
            ELSE NULL
        END AS DaysToClose,
        COUNT(DISTINCT c.Id) AS CommenterCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount,
        STRING_AGG(DISTINCT tag.TagName, ', ') AS Tags,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequence
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT p2.Id AS PostId,
               REPLACE(REPLACE(REPLACE(value, '<', ''), '>', ''), '/', '') AS TagName
        FROM Posts p2,
             UNNEST(STRING_TO_ARRAY(SUBSTRING(p2.Tags FROM 2 FOR CHAR_LENGTH(p2.Tags)-2), '><')) AS value
    ) AS tag ON p.Id = tag.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.PostTypeId, pt.Name, p.OwnerUserId, u.DisplayName, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
UserRank AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostHistoryCount,
        ua.CommentCount,
        ua.VoteCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TagWikiCount,
        ua.AvgPostScore,
        ua.GoldBadgeCount,
        ua.SilverBadgeCount,
        ua.BronzeBadgeCount,
        CASE WHEN ua.Reputation > 50000 THEN 'Expert'
             WHEN ua.Reputation > 10000 THEN 'Experienced'
             WHEN ua.Reputation > 1000 THEN 'Intermediate'
             ELSE 'Beginner'
        END AS ReputationLevel,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.PostHistoryCount DESC) AS UserRankNum
    FROM UserActivity ua
)
SELECT
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.ReputationLevel,
    ur.UserRankNum,
    ua.PostHistoryCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TagWikiCount,
    ua.AvgPostScore,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    ua.BronzeBadgeCount,
    (SELECT COUNT(*) FROM Posts pq WHERE pq.OwnerUserId = ur.UserId AND pq.PostTypeId = 1) AS TotalQuestionsOwned,
    (SELECT COUNT(*) FROM Posts pa WHERE pa.OwnerUserId = ur.UserId AND pa.PostTypeId = 2) AS TotalAnswersOwned,
    pe.PostId,
    pe.Title,
    pe.PostTypeName,
    pe.CreationDate AS PostCreationDate,
    pe.Score AS PostScore,
    pe.ViewCount AS PostViewCount,
    pe.AnswerCount AS PostAnswerCount,
    pe.CommentCount AS PostCommentCount,
    pe.FavoriteCount AS PostFavoriteCount,
    pe.ClosedDate AS PostClosedDate,
    pe.DaysToClose,
    pe.CommenterCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.FavoriteVoteCount,
    pe.Tags,
    COALESCE(pe.PostTypeName, 'Unknown') AS ProcessedPostTypeName,
    NULLIF(pe.Score, 0) AS NonZeroScore,
    CASE
        WHEN pe.PostTypeName = 'Question' AND pe.ClosedDate IS NULL THEN 'Open Question'
        WHEN pe.PostTypeName = 'Question' AND pe.ClosedDate IS NOT NULL THEN 'Closed Question'
        WHEN pe.PostTypeName = 'Answer' THEN 'Answer'
        ELSE 'Other'
    END AS QuestionStatus,
    CASE WHEN pe.PostTypeName = 'Question' THEN
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pe.PostId AND pl.LinkTypeId = 3)
    ELSE 0 END AS DuplicateLinkCount
FROM UserRank ur
JOIN UserActivity ua ON ur.UserId = ua.UserId
LEFT JOIN PostEngagement pe ON ur.UserId = pe.OwnerUserId
WHERE ur.UserRankNum <= 100
  AND (pe.PostSequence IS NULL OR pe.PostSequence <= 5)
  AND (pe.Score > 10 OR pe.CommentCount > 5 OR pe.FavoriteCount > 0)
ORDER BY ur.UserRankNum, pe.PostSequence;