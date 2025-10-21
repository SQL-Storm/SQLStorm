-- {"query": "27079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1932} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(v.VoteTypeId = 2) AS TotalUpVotes,
        SUM(v.VoteTypeId = 3) AS TotalDownvotes
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.LastAccessDate
),

PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountInPost,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankInOwnerPosts
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
),

BadgeSummary AS(
    SELECT
        b.UserId,
        u.DisplayName AS UserName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM
        Badges b
    JOIN
        Users u ON b.UserId = u.Id
    GROUP BY
        b.UserId, u.DisplayName
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryUser,
        u.DisplayName AS HistoryUserDisplayName,
        ph.Comment,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryDate,

        SUBSTRING(ph.Text,1,1000) TextSnippet,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (33, 34) THEN 1 ELSE 0 END)  as PostNoticeChanges,
        CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN JSON_EXTRACT(ph.Text, '"$.OriginalQuestionIds[0]"') ELSE NULL END AS OriginalQuestionId,
        CASE WHEN ph.PostHistoryTypeId=17 THEN JSON_UNQUOTE(JSON_EXTRACT(ph.Text, '$.url')) ELSE NULL END AS MigrationUrl
    FROM
        PostHistory ph
    LEFT JOIN
        Users u ON ph.UserId = u.Id
)

SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.LastAccessDate,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalBadges,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalPostScore,
    ua.TotalUpVotes,
    ua.TotalDownvotes,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bs.TagBasedBadges, 0) AS TagBasedBadges,
    pa.PostId,
    pa.PostTypeId,
    pa.CreationDate,
    pa.Score,
    pa.ViewCount,
    pa.Title,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    pa.RankInOwnerPosts,
    (ua.TotalPostScore - COALESCE(pa.PreviousScore, 0)) AS ScoreChange,
    phd.TextSnippet,
    phd.PreviousHistoryDate,
    phd.NextHistoryDate,
    UPPER(LEFT(ua.DisplayName,1)) || LOWER(SUBSTRING(ua.DisplayName FROM 2)) modifiedNameCaseChange,
    phd.PostId AS PostHistoryId,
    phd.HistoryUser,
    phd.HistoryUserDisplayName,
    phd.Comment,
    phd.PostHistoryTypeId,
    phd.OriginalQuestionId,
    previousQuestion.Title AS PreviousQuestionTitle,
    phd.MigrationUrl,
    destinationurl.text AS migrationDesinationUrlText,
    migratedFrom.Title AS migratedfromTitle

FROM
    UserActivity ua
LEFT JOIN
    PostActivity pa ON ua.UserId = pa.OwnerUserId
LEFT JOIN
    BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN
    PostHistoryDetails phd ON pa.PostId = phd.PostId
    left join (select distinct PostId, Title from Posts) as previousQuestion on phd.OriginalQuestionId = previousQuestion.PostId
    left join (select TextSnippet as Text, PostId as migrationUrlPostId from PostHistoryDetails) as destinationurl on phd.MigrationUrl=destinationurl.migrationUrlPostId
    left join (select Id as migrationfromPostId, Title from Posts) as migratedFrom on destinationurl.migrationUrlPostId=migratedFrom.migrationfromPostId
    WHERE CONCAT(ua.UserId, '-', pa.PostId) = (SELECT CONCAT(UserId, '-', PostId)
                                             FROM Posts
                                             WHERE CreationDate = (SELECT MAX(CreationDate) FROM Posts)
                                             AND OwnerUserId = (SELECT MAX(OwnerUserId) FROM Posts))
      OR phd.PostHistoryTypeId = (SELECT MAX(PostHistoryTypeId) FROM PostHistoryDetails);
