-- {"query": "3354.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1634} 
WITH UserActivity AS (
    SELECT 
        u.Id                                      AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COALESCE(SUM(
            CASE v.VoteTypeId
                WHEN 2 THEN 1      -- UpMod
                WHEN 3 THEN -1     -- DownMod
                ELSE 0
            END),0)                               AS NetPostVotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TimesClosed,
        MAX(u.Reputation)                         AS Reputation
    FROM Users u
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v       ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),

BadgeScores AS (
    SELECT 
        b.UserId,
        SUM(CASE b.Class
                WHEN 1 THEN 100   -- Gold
                WHEN 2 THEN  50   -- Silver
                ELSE   10         -- Bronze
            END) AS BadgePoints
    FROM Badges b
    GROUP BY b.UserId
),

TagContribution AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        COUNT(*)                              AS TagEdits,
        STRING_AGG(DISTINCT t.TagName, ',')   AS TagsEdited
    FROM Posts p
    JOIN PostHistory ph 
         ON ph.PostId = p.Id 
        AND ph.PostHistoryTypeId IN (4,5,6)   -- edits to title/body/tags
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(p.Tags, '><')) AS RawTag
    ) AS pt ON true
    JOIN Tags t 
         ON t.TagName = trim(both '<>' FROM pt.RawTag)
    GROUP BY p.OwnerUserId
),

Combined AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.NetPostVotes,
        ua.TimesClosed,
        COALESCE(bs.BadgePoints,0) AS BadgePoints,
        COALESCE(tc.TagEdits,0)    AS TagEdits,
        tc.TagsEdited,
        /* weighted activity score */
        ( ua.QuestionsPosted * 2
        + ua.AnswersPosted   * 3
        + ua.NetPostVotes    * 1
        + bs.BadgePoints    * 0.5
        - ua.TimesClosed    * 5 ) AS ActivityScore,
        ROW_NUMBER() OVER (ORDER BY 
            ( ua.QuestionsPosted * 2
            + ua.AnswersPosted   * 3
            + ua.NetPostVotes    * 1
            + bs.BadgePoints    * 0.5
            - ua.TimesClosed    * 5 ) DESC) AS RankOverall
    FROM UserActivity ua
    LEFT JOIN BadgeScores   bs ON bs.UserId = ua.UserId
    LEFT JOIN TagContribution tc ON tc.UserId = ua.UserId
)

SELECT 
    UserId,
    DisplayName,
    QuestionsPosted,
    AnswersPosted,
    NetPostVotes,
    TimesClosed,
    BadgePoints,
    TagEdits,
    TagsEdited,
    ROUND(ActivityScore,2) AS ActivityScore,
    RankOverall
FROM Combined
WHERE RankOverall <= 100

UNION ALL

SELECT 
    NULL      AS UserId,
    '--- Summary ---' AS DisplayName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    ROUND(AVG(ActivityScore),2) AS ActivityScore,
    NULL      AS RankOverall
FROM Combined

ORDER BY RankOverall NULLS LAST;