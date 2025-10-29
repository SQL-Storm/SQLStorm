-- {"query": "3869.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2051} 

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
       AND p.Tags LIKE '%' + '<' + t.TagName + '>' + '%'
    GROUP BY t.TagName
),
RecentActivity AS (
    SELECT 
        p.OwnerUserId,
        MAX(p.CreationDate)   AS LastPostDate,
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
        COALESCE(ra.LastPostDate,      CAST('1970-01-01' AS datetime)) AS LastPostDate,
        COALESCE(ra.LastActivityDate, CAST('1970-01-01' AS datetime)) AS LastActivityDate,
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
    CommentCount
FROM Combined
WHERE (LastActivityDate > DATEADD(day, -30, GETDATE()))
   OR (QuestionCount > 10 AND AnswerCount = 0)
ORDER BY Reputation DESC, GoldBadges DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY

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
    0               AS CommentCount
FROM Combined
WHERE Reputation BETWEEN 500 AND 999
ORDER BY Reputation ASC;
