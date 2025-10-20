-- {"query": "39007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3796} 

WITH UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(c.Id) AS CommentsCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        DATEDIFF(DAY, u.CreationDate, u.LastAccessDate) AS DaysActive
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    LEFT JOIN Votes    v ON v.PostId      = p.Id
    GROUP BY 
        u.Id, 
        u.DisplayName, 
        u.CreationDate, 
        u.LastAccessDate
),
TagMetrics AS (
    SELECT 
        qt.TagName,
        COUNT(DISTINCT q.Id) AS QuestionCount,
        COUNT(a.Id)        AS AnswerCount,
        AVG(q.Score)       AS AvgQuestionScore,
        AVG(a.Score)       AS AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(a.Id) DESC) AS AnswerRank
    FROM Posts q
    JOIN Posts a 
      ON a.ParentId   = q.Id 
     AND a.PostTypeId = 2
    CROSS APPLY (
        SELECT value AS TagName
        FROM STRING_SPLIT(
             REPLACE(REPLACE(q.Tags, '<', ''), '>', ','), 
             ','
        )
        WHERE value <> ''
    ) AS qt
    WHERE q.PostTypeId = 1
    GROUP BY 
        qt.TagName
),
RankedBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        RANK() OVER (
          PARTITION BY b.UserId 
          ORDER BY b.Date DESC
        ) AS RecentBadgeRank
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    tm.TagName,
    tm.QuestionCount,
    tm.AnswerCount,
    tm.AvgQuestionScore,
    tm.AvgAnswerScore,
    ua.PostsCount,
    ua.CommentsCount,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.DaysActive,
    rb.GoldBadges,
    rb.SilverBadges,
    rb.BronzeBadges
FROM TagMetrics tm
CROSS APPLY (
    SELECT TOP 1
        ua2.PostsCount,
        ua2.CommentsCount,
        ua2.UpVotesReceived,
        ua2.DownVotesReceived,
        ua2.DaysActive,
        ua2.Id
    FROM UserActivity ua2
    WHERE ua2.Id IN (
        SELECT TOP 1 p.OwnerUserId
        FROM Posts p
        WHERE p.Tags LIKE '%<' + tm.TagName + '>%'
        GROUP BY p.OwnerUserId
        ORDER BY COUNT(*) DESC
    )
) AS ua
LEFT JOIN RankedBadges rb
    ON rb.UserId        = ua.Id
   AND rb.RecentBadgeRank = 1
WHERE 
    tm.QuestionCount > 500
    AND ua.PostsCount > 1000
ORDER BY 
    tm.AnswerCount      DESC,
    ua.UpVotesReceived  DESC
OPTION (MAXDOP 8);
