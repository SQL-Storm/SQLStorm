WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
TagActivity AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LatestQuestion,
        STRING_AGG(DISTINCT SUBSTRING(p.Title FROM 1 FOR 30), '; ') AS SampleTitles
    FROM Tags t
    JOIN Posts p
        ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
TopUserPosts AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.UpVoteCount,
    us.DownVoteCount,
    us.LastPostDate,
    tp.PostId,
    tp.Title,
    tp.Score,
    COALESCE(tact.QuestionCount, 0) AS TagQuestionCount,
    COALESCE(tact.TotalScore, 0) AS TagTotalScore,
    tact.LatestQuestion,
    tact.SampleTitles
FROM UserStats us
LEFT JOIN TopUserPosts tp
       ON tp.OwnerUserId = us.Id AND tp.rn = 1
LEFT JOIN LATERAL (
    SELECT ta.TagName, ta.QuestionCount, ta.TotalScore, ta.LatestQuestion, ta.SampleTitles
    FROM TagActivity ta
    WHERE EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
          AND p.Tags LIKE '%' || ta.TagName || '%'
          AND p.PostTypeId = 1
    )
    ORDER BY ta.TotalScore DESC
    LIMIT 1
) tact ON TRUE
WHERE (us.Reputation > 10000 OR us.GoldBadges > 5)
  AND us.LastPostDate IS NOT NULL
  AND us.LastPostDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'

UNION ALL

SELECT
    NULL AS Id,
    'Aggregate' AS DisplayName,
    SUM(us.Reputation) AS Reputation,
    SUM(us.NetVotes) AS NetVotes,
    SUM(us.GoldBadges) AS GoldBadges,
    SUM(us.SilverBadges) AS SilverBadges,
    SUM(us.BronzeBadges) AS BronzeBadges,
    SUM(us.UpVoteCount) AS UpVoteCount,
    SUM(us.DownVoteCount) AS DownVoteCount,
    MAX(us.LastPostDate) AS LastPostDate,
    NULL AS PostId,
    NULL AS Title,
    NULL AS Score,
    SUM(tact.QuestionCount) AS TagQuestionCount,
    SUM(tact.TotalScore) AS TagTotalScore,
    MAX(tact.LatestQuestion) AS LatestTagQuestion,
    STRING_AGG(tact.SampleTitles, ' | ') AS SampleTitles
FROM UserStats us
LEFT JOIN TagActivity tact ON TRUE
WHERE us.Reputation > 5000;