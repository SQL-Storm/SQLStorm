WITH
    recent_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.Tags,
            p.OwnerUserId,
            p.AcceptedAnswerId,
            p.AnswerCount
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '180 days'
    ),
    answer_aggregates AS (
        SELECT
            a.ParentId AS QuestionId,
            COUNT(*)                         AS TotalAnswers,
            AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgScore,
            MAX(a.CreationDate)              AS LatestAnswerDate
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ),
    user_activity AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(b.BadgeCnt, 0)                AS BadgeCount,
            COALESCE(v.UpVoteCnt, 0)               AS UpVotesGiven,
            COALESCE(v.DownVoteCnt, 0)             AS DownVotesGiven,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS RepRank
        FROM Users u
        LEFT JOIN (
            SELECT UserId, COUNT(*) AS BadgeCnt
            FROM Badges
            GROUP BY UserId
        ) b ON b.UserId = u.Id
        LEFT JOIN (
            SELECT
                UserId,
                COUNT(*) FILTER (WHERE VoteTypeId = 2) AS UpVoteCnt,
                COUNT(*) FILTER (WHERE VoteTypeId = 3) AS DownVoteCnt
            FROM Votes
            GROUP BY UserId
        ) v ON v.UserId = u.Id
    ),
    tag_stats AS (
        SELECT
            tag,
            COUNT(*)                                    AS TagUseCount,
            SUM(CASE WHEN score > 0 THEN 1 ELSE 0 END)  AS PositiveScorePosts
        FROM (
            SELECT
                UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag,
                p.Score AS score
            FROM Posts p
            WHERE p.Tags IS NOT NULL
        ) t
        GROUP BY tag
    ),
    recent_badges AS (
        SELECT
            b.UserId,
            b.Name,
            b.Date
        FROM Badges b
        WHERE b.Date >= CAST('2024-10-01' AS DATE) - INTERVAL '30 days'
    ),
    closed_q AS (
        SELECT
            ph.PostId,
            ph.CreationDate AS ClosedOn,
            CAST(ph.Comment AS INTEGER) AS CloseReasonId
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
    )
SELECT
    rq.Id                              AS QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    COALESCE(aa.TotalAnswers, 0)       AS AnswerCountCalculated,
    COALESCE(aa.AvgScore, 0)           AS AvgAnswerScore,
    ua.DisplayName                     AS OwnerName,
    ua.Reputation,
    ua.BadgeCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ts.TagUseCount,
    ts.PositiveScorePosts,
    rb.Name                            AS RecentBadgeName,
    rb.Date                            AS RecentBadgeDate,
    cq.ClosedOn,
    CASE
        WHEN cq.CloseReasonId IS NULL THEN 'Open'
        WHEN cq.CloseReasonId = 101      THEN 'Duplicate'
        WHEN cq.CloseReasonId = 102      THEN 'Off-topic'
        ELSE                               'Other'
    END                                 AS CloseReasonDesc,
    ROW_NUMBER() OVER (ORDER BY rq.Score DESC, rq.ViewCount DESC) AS RankByScore
FROM recent_questions rq
LEFT JOIN answer_aggregates aa ON aa.QuestionId = rq.Id
LEFT JOIN user_activity ua     ON ua.UserId = rq.OwnerUserId
LEFT JOIN LATERAL (
    SELECT
        SUM(ts2.TagUseCount)        AS TagUseCount,
        SUM(ts2.PositiveScorePosts) AS PositiveScorePosts
    FROM (
        SELECT UNNEST(string_to_array(trim(both '<>' FROM rq.Tags), '><')) AS individual_tag
    ) tg
    LEFT JOIN tag_stats ts2 ON ts2.tag = tg.individual_tag
) ts ON TRUE
LEFT JOIN recent_badges rb ON rb.UserId = rq.OwnerUserId
LEFT JOIN closed_q cq    ON cq.PostId = rq.Id
WHERE
    (rq.Score > 0 OR rq.ViewCount IS NULL OR rq.ViewCount > 100)
    AND (rq.Tags IS NOT NULL AND rq.Tags <> '')
UNION ALL
SELECT
    q.Id,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    0                                   AS AnswerCountCalculated,
    NULL                                AS AvgAnswerScore,
    u.DisplayName,
    u.Reputation,
    0                                   AS BadgeCount,
    0                                   AS UpVotesGiven,
    0                                   AS DownVotesGiven,
    0                                   AS TagUseCount,
    0                                   AS PositiveScorePosts,
    NULL                                AS RecentBadgeName,
    NULL                                AS RecentBadgeDate,
    NULL                                AS ClosedOn,
    'Open'                              AS CloseReasonDesc,
    ROW_NUMBER() OVER (ORDER BY q.CreationDate DESC) AS RankByScore
FROM Posts q
JOIN Users u ON u.Id = q.OwnerUserId
WHERE q.PostTypeId = 1
  AND NOT EXISTS (
      SELECT 1 FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2
  )
  AND q.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '180 days';