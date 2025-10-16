WITH
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                              AS QuestionCount,
        SUM(p.Score)                             AS TotalScore,
        SUM(p.ViewCount)                         AS TotalViews,
        AVG(p.Score)                             AS AvgScore,
        AVG(p.ViewCount)                         AS AvgViews
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '><' FROM p.Tags), '><')) AS Tag
    ) AS pt ON TRUE
    JOIN Tags t ON t.TagName = pt.Tag
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),

UserAgg AS (
    SELECT
        u.Id                                               AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.Gold,   0)                               AS GoldBadges,
        COALESCE(b.Silver, 0)                               AS SilverBadges,
        COALESCE(b.Bronze, 0)                               AS BronzeBadges,
        COALESCE(v.UpVotes,   0)                            AS UpVotesReceived,
        COALESCE(v.DownVotes, 0)                            AS DownVotesReceived
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) v ON v.OwnerUserId = u.Id
),

RankedQuestions AS (
    SELECT
        pt.Tag AS TagName,
        p.Id                             AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY pt.Tag
            ORDER BY p.Score DESC, p.ViewCount DESC
        )                                 AS RankInTag
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '><' FROM p.Tags), '><')) AS Tag
    ) pt ON TRUE
    WHERE p.PostTypeId = 1
),

CommentStats AS (
    SELECT
        c.PostId,
        COUNT(*)                                    AS CommentCount,
        AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),

TopTagQuestions AS (
    SELECT
        rs.TagName,
        rs.PostId,
        rs.Title,
        rs.Score,
        rs.ViewCount,
        u.DisplayName,
        u.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        COALESCE(cs.CommentCount, 0)               AS CommentCount,
        COALESCE(cs.AvgCommentScore, 0)            AS AvgCommentScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL                     THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL               THEN 'Answered'
            ELSE 'Open'
        END                                          AS Status,
        'https://stackoverflow.com/q/' || rs.PostId    AS Url,
        (p.Score * COALESCE(cs.CommentCount,1) /
         NULLIF(p.ViewCount,0) + u.Reputation/1000.0)      AS CompositeScore
    FROM RankedQuestions rs
    JOIN Posts p            ON p.Id = rs.PostId
    LEFT JOIN Users u       ON u.Id = p.OwnerUserId
    LEFT JOIN UserAgg ua    ON ua.UserId = u.Id
    LEFT JOIN CommentStats cs ON cs.PostId = p.Id
    WHERE rs.RankInTag <= 5
)

SELECT *
FROM TopTagQuestions
WHERE Reputation > 1000
  AND (Score > 10 OR ViewCount > 5000)
  AND (GoldBadges + SilverBadges + BronzeBadges) > 5

UNION ALL

SELECT
    NULL                                          AS TagName,
    q.Id                                          AS PostId,
    q.Title,
    q.Score,
    q.ViewCount,
    u.DisplayName,
    u.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    COALESCE(cs.CommentCount, 0)                 AS CommentCount,
    COALESCE(cs.AvgCommentScore, 0)              AS AvgCommentScore,
    'Closed'                                      AS Status,
    'https://stackoverflow.com/q/' || q.Id       AS Url,
    (q.Score * COALESCE(cs.CommentCount,1) /
     NULLIF(q.ViewCount,0) + u.Reputation/1000.0)  AS CompositeScore
FROM Posts q
LEFT JOIN Users u          ON u.Id = q.OwnerUserId
LEFT JOIN UserAgg ua       ON ua.UserId = u.Id
LEFT JOIN CommentStats cs  ON cs.PostId = q.Id
WHERE q.PostTypeId = 1
  AND q.ClosedDate IS NOT NULL
  AND q.Score < 0
  AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.PostId = q.Id
          AND ph.PostHistoryTypeId = 10
          AND ph.Comment LIKE '101%'
      )

ORDER BY Score DESC, ViewCount DESC
LIMIT 100;