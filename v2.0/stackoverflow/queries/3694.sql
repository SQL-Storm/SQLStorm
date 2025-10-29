WITH
recent_questions AS (
    SELECT
        p.Id                              AS QId,
        p.Title,
        p.CreationDate,
        p.Score                           AS QScore,
        p.ViewCount,
        p.OwnerUserId,
        unnest(
            string_to_array(
                substring(p.Tags FROM 2 FOR char_length(p.Tags)-2),
                '><'
            )
        )                                 AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
),
user_activity AS (
    SELECT
        u.Id                                 AS UserId,
        u.DisplayName,
        COUNT(p.Id)                           AS TotalPosts,
        SUM(COALESCE(p.Score,0))              AS TotalScore,
        AVG(COALESCE(p.ViewCount,0))          AS AvgViews,
        MAX(u.Reputation)                     AS MaxReputation,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b    ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
answer_stats AS (
    SELECT
        q.Id                                 AS QId,
        COUNT(a.Id)                          AS AnswerCount,
        SUM(CASE WHEN a.Score > q.Score THEN 1 ELSE 0 END) AS BetterAnswers,
        AVG(COALESCE(a.Score,0))             AS AvgAnswerScore,
        MAX(a.CreationDate)                 AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
vote_summary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) AS DownVotes,
        SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
),
tag_popularity AS (
    SELECT
        t.TagName,
        COALESCE(t.Count,0)                           AS TagCount,
        COALESCE(pcnt.PostsWithTag,0)                AS PostsWithTag
    FROM Tags t
    FULL OUTER JOIN (
        SELECT Tag, COUNT(DISTINCT QId) AS PostsWithTag
        FROM recent_questions
        GROUP BY Tag
    ) pcnt ON pcnt.Tag = t.TagName
),
duplicate_links AS (
    SELECT
        pl.PostId      AS SourceId,
        pl.RelatedPostId,
        lt.Name        AS LinkType,
        pl.CreationDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Id IN (1,3)
),
question_or_wiki AS (
    SELECT
        q.Id           AS EntityId,
        q.Title        AS Title,
        q.CreationDate,
        'question'     AS EntityType,
        rq.Tag
    FROM Posts q
    JOIN recent_questions rq ON rq.QId = q.Id
    WHERE q.PostTypeId = 1

    UNION ALL

    SELECT
        tw.Id          AS EntityId,
        tw.Title       AS Title,
        tw.CreationDate,
        'tag_wiki'     AS EntityType,
        t.TagName
    FROM Posts tw
    JOIN Tags t ON t.WikiPostId = tw.Id
    WHERE tw.PostTypeId IN (5,4)
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalScore,
    ua.AvgViews,
    ua.MaxReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    q.Title,
    q.CreationDate               AS QuestionDate,
    q.QScore,
    q.ViewCount,
    q.Tag,
    COALESCE(asr.AnswerCount,0)  AS AnswerCount,
    COALESCE(asr.BetterAnswers,0) AS BetterAnswers,
    COALESCE(vs.UpVotes,0)       AS UpVotes,
    COALESCE(vs.DownVotes,0)     AS DownVotes,
    COALESCE(vs.Favorites,0)     AS Favorites,
    ROW_NUMBER() OVER (PARTITION BY q.Tag ORDER BY q.CreationDate DESC) AS TagRank,
    LAG(q.CreationDate) OVER (PARTITION BY q.Tag ORDER BY q.CreationDate) AS PrevQuestionDate,
    LEAD(q.CreationDate) OVER (PARTITION BY q.Tag ORDER BY q.CreationDate) AS NextQuestionDate,
    COALESCE(dl.LinkType, 'none') AS LinkType,
    COALESCE(dl.RelatedPostId, -1) AS RelatedPostId,
    COALESCE(tp.TagCount,0)      AS TagGlobalCount,
    COALESCE(tp.PostsWithTag,0)  AS RecentPostsWithTag
FROM user_activity ua
LEFT JOIN Posts p            ON p.OwnerUserId = ua.UserId
LEFT JOIN recent_questions q ON q.QId = p.Id
LEFT JOIN answer_stats asr   ON asr.QId = q.QId
LEFT JOIN vote_summary vs    ON vs.PostId = q.QId
LEFT JOIN duplicate_links dl ON dl.SourceId = q.QId
LEFT JOIN tag_popularity tp  ON tp.TagName = q.Tag
WHERE ua.TotalPosts > 10
  AND (ua.GoldBadges > 0 OR ua.SilverBadges > 1)
  AND q.QScore IS NOT NULL
  AND (q.ViewCount > 100 OR COALESCE(vs.Favorites,0) > 5)
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalScore,
    ua.AvgViews,
    ua.MaxReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    q.Title,
    q.CreationDate,
    q.QScore,
    q.ViewCount,
    q.Tag,
    asr.AnswerCount,
    asr.BetterAnswers,
    vs.UpVotes,
    vs.DownVotes,
    vs.Favorites,
    q.CreationDate,
    q.Tag,
    dl.LinkType,
    dl.RelatedPostId,
    tp.TagCount,
    tp.PostsWithTag
ORDER BY ua.TotalScore DESC, q.CreationDate DESC
LIMIT 200;