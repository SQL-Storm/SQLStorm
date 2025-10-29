WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                                            AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)      AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)      AS Answers,
        AVG(COALESCE(p.Score,0))                               AS AvgScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC)         AS TagRank
    FROM Tags t
    LEFT JOIN Posts p 
        ON p.Tags IS NOT NULL 
       AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName
),
RecentActivity AS (
    SELECT 
        p.OwnerUserId,
        MAX(p.CreationDate)    AS LastPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        COALESCE(ra.LastPostDate,      TIMESTAMP '1970-01-01 00:00:00') AS LastPostDate,
        COALESCE(ra.LastActivityDate,  TIMESTAMP '1970-01-01 00:00:00') AS LastActivityDate,
        (SELECT STRING_AGG(t.TagName, ', ') 
         FROM TagStats t 
         WHERE t.TagRank <= 5)                         AS Top5Tags,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = us.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = us.Id AND v.VoteTypeId = 3) AS DownVotesGiven,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.Id)                AS CommentCount
    FROM UserStats us
    LEFT JOIN RecentActivity ra 
        ON ra.OwnerUserId = us.Id
    WHERE us.Reputation > 1000
      AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 0
)
SELECT *
FROM (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        QuestionCount,
        AnswerCount,
        LastPostDate,
        LastActivityDate,
        Top5Tags,
        UpVotesGiven,
        DownVotesGiven,
        CommentCount,
        1 AS result_order,
        Reputation AS sort_reputation,
        GoldBadges AS sort_gold
    FROM Combined
    WHERE (LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 day'))
       OR (QuestionCount > 10 AND AnswerCount = 0)

    UNION ALL

    SELECT 
        Id,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        QuestionCount,
        AnswerCount,
        LastPostDate,
        LastActivityDate,
        NULL            AS Top5Tags,
        0               AS UpVotesGiven,
        0               AS DownVotesGiven,
        0               AS CommentCount,
        2 AS result_order,
        Reputation AS sort_reputation,
        GoldBadges AS sort_gold
    FROM Combined
    WHERE Reputation BETWEEN 500 AND 999
) AS unioned
ORDER BY result_order, 
         -- first part: Reputation DESC, GoldBadges DESC; second part: Reputation ASC
         CASE WHEN result_order = 1 THEN sort_reputation END DESC,
         CASE WHEN result_order = 1 THEN sort_gold END DESC,
         CASE WHEN result_order = 2 THEN sort_reputation END ASC
LIMIT 100 OFFSET 0;