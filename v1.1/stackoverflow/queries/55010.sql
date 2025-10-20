WITH 
    TagQuestions AS (
        SELECT 
            p.Id               AS QuestionId,
            regexp_replace(t.tag, '^<|>$', '') AS TagName
        FROM   Posts p,
               LATERAL (
                 SELECT regexp_matches(p.Tags, '>([^<]+)<', 'g') AS matches
               ) m
               CROSS JOIN LATERAL (SELECT unnest(matches)) AS t(tag)
        WHERE  p.PostTypeId = 1
          AND  p.Tags IS NOT NULL
    ),

    Answers AS (
        SELECT 
            a.Id               AS AnswerId,
            a.ParentId         AS QuestionId,
            a.OwnerUserId,
            a.Score,
            a.CreationDate
        FROM   Posts a
        WHERE  a.PostTypeId = 2
    ),

    UserStats AS (
        SELECT 
            u.Id                                AS UserId,
            u.Reputation,
            u.DisplayName,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotesReceived,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotesReceived,
            COUNT(b.Id)                         AS BadgeCount
        FROM   Users u
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v   ON v.PostId = p.Id
        LEFT JOIN Badges b  ON b.UserId = u.Id
        GROUP BY u.Id, u.Reputation, u.DisplayName
    ),

    TagUserScores AS (
        SELECT 
            tq.TagName,
            us.UserId,
            us.DisplayName,
            us.Reputation,
            COUNT(a.AnswerId)                                 AS AnswerCount,
            SUM(a.Score)                                      AS TotalAnswerScore,
            SUM(us.UpVotesReceived)                           AS TotalUpVotesReceived,
            SUM(us.BadgeCount)                                AS TotalBadgeCount,
            ROW_NUMBER() OVER (
                PARTITION BY tq.TagName 
                ORDER BY SUM(a.Score) DESC, us.Reputation DESC
            )                                                AS rn,
            a.QuestionId
        FROM   TagQuestions tq
        JOIN   Answers a          ON a.QuestionId = tq.QuestionId
        JOIN   UserStats us       ON us.UserId = a.OwnerUserId
        GROUP BY 
            tq.TagName,
            us.UserId,
            us.DisplayName,
            us.Reputation,
            a.QuestionId
    ),

    TagDupInfo AS (
        SELECT 
            t.TagName,
            COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount
        FROM   TagUserScores t
        LEFT JOIN PostLinks pl 
               ON pl.PostId = t.QuestionId AND pl.LinkTypeId = 3
        GROUP BY t.TagName
    )

SELECT 
    s.TagName,
    s.UserId,
    s.DisplayName,
    s.Reputation,
    s.AnswerCount,
    s.TotalAnswerScore,
    s.TotalUpVotesReceived,
    s.TotalBadgeCount,
    d.DuplicateCount
FROM   TagUserScores s
LEFT JOIN TagDupInfo d ON d.TagName = s.TagName
WHERE  s.rn <= 5
ORDER BY s.TagName, s.rn;