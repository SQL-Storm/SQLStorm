-- {"query": "3247.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2696} 

WITH UserStats AS (
    SELECT
        u.Id                                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)    AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)    AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)   AS AnswerScoreSum,
        MAX(p.CreationDate)                           AS LastPostDate,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name END) AS TagBasedBadgeCount,
        COUNT(DISTINCT CASE WHEN b.TagBased = 0 THEN b.Name END) AS NamedBadgeCount
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

RecentActivity AS (
    SELECT
        u.Id                                            AS UserId,
        MAX(v.CreationDate)                             AS LastVoteDate,
        MAX(c.CreationDate)                             AS LastCommentDate
    FROM Users u
    LEFT JOIN Votes    v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),

TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                         AS TagPostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p
      ON p.Tags IS NOT NULL
     AND t.TagName = ANY (string_to_array(trim(both '><' FROM p.Tags), '><'))
    GROUP BY t.TagName
),

UserTagParticipation AS (
    SELECT
        u.Id                                   AS UserId,
        t.TagName,
        COUNT(p.Id)                            AS PostsInTag,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRankForUser
    FROM Users u
    JOIN Posts p
      ON p.OwnerUserId = u.Id
    JOIN Tags  t
      ON t.TagName = ANY (string_to_array(trim(both '><' FROM p.Tags), '><'))
    GROUP BY u.Id, t.TagName
),

AcceptedAnswers AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(*)      AS AcceptedAnswerCount
    FROM Posts a
    JOIN Posts q ON q.AcceptedAnswerId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),

Combined AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        COALESCE(us.AnswerScoreSum,0) / NULLIF(us.AnswerCount,0)            AS AvgAnswerScore,
        us.TagBasedBadgeCount,
        us.NamedBadgeCount,
        ra.LastVoteDate,
        ra.LastCommentDate,
        aa.AcceptedAnswerCount,
        COALESCE(ra.LastVoteDate, ra.LastCommentDate, us.LastPostDate)     AS LastActivity,
        CASE
            WHEN us.Reputation > 20000 THEN 'Legendary'
            WHEN us.Reputation > 10000 THEN 'Expert'
            WHEN us.Reputation > 5000  THEN 'Experienced'
            ELSE 'Novice'
        END                                                                AS ReputationTier,
        (SELECT p.Title
         FROM Posts p
         WHERE p.OwnerUserId = us.UserId
         ORDER BY p.CreationDate DESC
         LIMIT 1)                                                         AS LatestPostTitle
    FROM UserStats        us
    LEFT JOIN RecentActivity   ra ON ra.UserId = us.UserId
    LEFT JOIN AcceptedAnswers  aa ON aa.UserId = us.UserId
),

FinalResult AS (
    SELECT
        c.*,
        utp.TagName,
        utp.PostsInTag,
        ROW_NUMBER() OVER (PARTITION BY c.UserId ORDER BY utp.PostsInTag DESC) AS UserTagRank
    FROM Combined c
    LEFT JOIN UserTagParticipation utp
           ON utp.UserId = c.UserId
    WHERE utp.TagRankForUser <= 3          -- top‑3 tags per user
)

SELECT
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.ReputationTier,
    fr.QuestionCount,
    fr.AnswerCount,
    ROUND(fr.AvgAnswerScore,2)              AS AvgAnswerScore,
    fr.TagBasedBadgeCount,
    fr.NamedBadgeCount,
    fr.AcceptedAnswerCount,
    fr.LastActivity,
    COALESCE(fr.LatestPostTitle,'(no posts)') AS LatestPostTitle,
    fr.TagName,
    fr.PostsInTag,
    fr.UserTagRank,
    CASE WHEN fr.TagName IS NULL THEN 0 ELSE 1 END AS HasTagInfo,
    -- set‑operator example: include a placeholder row for completely inactive users
    UNION ALL
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        CASE
            WHEN u.Reputation > 20000 THEN 'Legendary'
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 5000  THEN 'Experienced'
            ELSE 'Novice'
        END,
        0,0,0,0,0,0,NULL,'(inactive)','','',0,0
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts   p WHERE p.OwnerUserId = u.Id)
      AND NOT EXISTS (SELECT 1 FROM Votes   v WHERE v.UserId      = u.Id)
      AND NOT EXISTS (SELECT 1 FROM Comments c WHERE c.UserId      = u.Id)
)
ORDER BY Reputation DESC, UserTagRank NULLS LAST
LIMIT 100;
