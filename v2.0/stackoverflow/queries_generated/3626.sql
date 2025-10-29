-- {"query": "3626.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2991} 

WITH
    QuestionStats AS (
        SELECT
            p.Id                              AS QuestionId,
            p.Title,
            p.CreationDate,
            p.Score                           AS QuestionScore,
            p.ViewCount,
            p.FavoriteCount,
            COALESCE(u.Reputation, 0)         AS OwnerReputation,
            COUNT(a.Id) FILTER (WHERE a.Score > 0)  AS PositiveAnswerCount,
            COUNT(a.Id) FILTER (WHERE a.Score <= 0) AS NonPositiveAnswerCount,
            MAX(a.CreationDate)               AS LastAnswerDate,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS ViewRank
        FROM Posts p
        LEFT JOIN Users u      ON p.OwnerUserId = u.Id
        LEFT JOIN Posts a      ON a.ParentId = p.Id AND a.PostTypeId = 2
        LEFT JOIN Votes v      ON v.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.FavoriteCount, u.Reputation
    ),
    TagExtraction AS (
        SELECT
            q.Id                                 AS QuestionId,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM q.Tags), '><')) AS Tag
        FROM Posts q
        WHERE q.PostTypeId = 1
    ),
    TagStats AS (
        SELECT
            te.QuestionId,
            t.TagName,
            t.Count                              AS TagGlobalCount,
            COALESCE(SUM(qs.QuestionScore), 0)    AS TotalScoreForTag,
            ROW_NUMBER() OVER (PARTITION BY te.QuestionId ORDER BY t.Count DESC) AS TagRankByPopularity
        FROM TagExtraction te
        JOIN Tags t          ON t.TagName = te.Tag
        JOIN QuestionStats qs ON qs.QuestionId = te.QuestionId
        GROUP BY te.QuestionId, t.TagName, t.Count
    ),
    BadgeAgg AS (
        SELECT
            b.UserId,
            STRING_AGG(b.Name, ', ' ORDER BY b.Class) AS BadgesList,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount
        FROM Badges b
        GROUP BY b.UserId
    ),
    RecentComments AS (
        SELECT
            c.PostId,
            STRING_AGG(CONCAT(c.UserDisplayName, ': ', LEFT(c.Text, 30)), '; '
                       ORDER BY c.CreationDate DESC) AS RecentCommentSnippets
        FROM Comments c
        WHERE c.CreationDate >= NOW() - INTERVAL '30 days'
        GROUP BY c.PostId
    ),
    ClosedReasonCTE AS (
        SELECT
            ph.PostId,
            ct.Name                         AS CloseReason,
            ph.CreationDate                 AS ClosedDate
        FROM PostHistory ph
        JOIN CloseReasonTypes ct ON ct.Id::text = ph.Comment
        WHERE ph.PostHistoryTypeId = 10
    ),
    UnionSet AS (
        SELECT
            qs.QuestionId                 AS PostId,
            qs.Title,
            qs.OwnerReputation,
            qs.ViewCount,
            qs.ViewRank,
            qs.QuestionScore,
            qs.FavoriteCount,
            ts.TagName,
            ts.TagGlobalCount,
            ts.TagRankByPopularity,
            ba.BadgesList,
            rc.RecentCommentSnippets,
            cr.CloseReason,
            cr.ClosedDate,
            'Question'                    AS PostCategory
        FROM QuestionStats qs
        LEFT JOIN TagStats ts          ON ts.QuestionId = qs.QuestionId
        LEFT JOIN Posts p              ON p.Id = qs.QuestionId
        LEFT JOIN Users u              ON p.OwnerUserId = u.Id
        LEFT JOIN BadgeAgg ba          ON ba.UserId = u.Id
        LEFT JOIN RecentComments rc    ON rc.PostId = qs.QuestionId
        LEFT JOIN ClosedReasonCTE cr   ON cr.PostId = qs.QuestionId
        WHERE qs.ViewRank <= 1000

        UNION ALL

        SELECT
            a.Id                          AS PostId,
            a.Title,
            COALESCE(u.Reputation, 0)     AS OwnerReputation,
            a.ViewCount,
            ROW_NUMBER() OVER (ORDER BY a.ViewCount DESC) AS ViewRank,
            a.Score,
            a.FavoriteCount,
            NULL                          AS TagName,
            NULL                          AS TagGlobalCount,
            NULL                          AS TagRankByPopularity,
            ba.BadgesList,
            rc.RecentCommentSnippets,
            cr.CloseReason,
            cr.ClosedDate,
            'Answer'                      AS PostCategory
        FROM Posts a
        JOIN Posts q                  ON q.Id = a.ParentId AND q.PostTypeId = 1
        LEFT JOIN Users u             ON a.OwnerUserId = u.Id
        LEFT JOIN BadgeAgg ba         ON ba.UserId = u.Id
        LEFT JOIN RecentComments rc   ON rc.PostId = a.Id
        LEFT JOIN ClosedReasonCTE cr  ON cr.PostId = a.Id
        WHERE a.PostTypeId = 2
    )
SELECT
    us.PostId,
    us.Title,
    us.OwnerReputation,
    us.ViewCount,
    us.ViewRank,
    us.QuestionScore,
    us.FavoriteCount,
    COALESCE(us.TagName, 'N/A')               AS PrimaryTag,
    us.TagGlobalCount,
    us.TagRankByPopularity,
    us.BadgesList,
    us.RecentCommentSnippets,
    COALESCE(us.CloseReason, 'Open')          AS CurrentStatus,
    us.ClosedDate,
    us.PostCategory,
    CASE
        WHEN us.QuestionScore >= 10 THEN 'Hot'
        WHEN us.ViewCount > 1000      THEN 'Popular'
        ELSE 'Regular'
    END                                        AS EngagementTier,
    (us.OwnerReputation * COALESCE(us.QuestionScore, 0) + COALESCE(us.FavoriteCount, 0) * 2) AS ReputationScore
FROM UnionSet us
ORDER BY us.PostCategory, us.ViewRank
LIMIT 500;
