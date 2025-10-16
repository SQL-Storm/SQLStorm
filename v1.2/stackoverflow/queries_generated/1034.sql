-- {"query": "1034.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1662} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.PostTypeId,
        u.Id as OwnerUserId,
        u.Reputation,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Tags ilike '%' || t.TagName || '%'
    left join Users u on p.OwnerUserId = u.Id
    where t.IsModeratorOnly = 0 and p.PostTypeId in (1, 2)
),
LatestPostsPerTag as (
    select
        Id, TagName, Count, PostId, PostTypeId, OwnerUserId, Reputation, DisplayName
    from RecursiveTagCounts
    where rn = 1
),
VotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteCount
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) filter (where p.Score > 5) as HighScoreAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadges as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgePivot as (
    select
        ub.UserId,
        max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadges ub
    group by ub.UserId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
QuestionsWithDetails as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(vs.UpVotes,0) as UpVotes,
        coalesce(vs.DownVotes,0) as DownVotes,
        coalesce(vs.FavoriteCount,0) as FavoriteCount,
        coalesce(ans.HighScoreAnswers,0) as HighScoreAnswers,
        coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(ubp.GoldBadges,0) as GoldBadges,
        coalesce(ubp.SilverBadges,0) as SilverBadges,
        coalesce(ubp.BronzeBadges,0) as BronzeBadges,
        cr.CloseReasonName,
        cr.CloseDate
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join VotesSummary vs on vs.PostId = p.Id
    left join AnswerStats ans on ans.QuestionId = p.Id
    left join UserBadgePivot ubp on ubp.UserId = p.OwnerUserId
    left join PostCloseReasons cr on cr.PostId = p.Id
    where p.PostTypeId = 1
),
RankedQuestions as (
    select
        qwd.*,
        dense_rank() over (partition by coalesce(qwd.CloseReasonName, 'OPEN') order by qwd.Score desc, qwd.ViewCount desc) as RankWithinCloseReason
    from QuestionsWithDetails qwd
),
QuestionsWithCommentCount as (
    select
        rq.*,
        (select count(*) from Comments c where c.PostId = rq.Id) as CommentCount,
        (select array_agg(distinct pht.Name order by ph.CreationDate) 
            from PostHistory ph
            join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
            where ph.PostId = rq.Id and ph.CreationDate > rq.CreationDate limit 5) as RecentHistoryTypes
    from RankedQuestions rq
),
ClosedQuestionsAndDuplicates as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.DisplayName,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.UpVotes,
        q.DownVotes,
        q.FavoriteCount,
        q.HighScoreAnswers,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.CloseReasonName,
        q.CloseDate,
        q.RankWithinCloseReason,
        q.CommentCount,
        q.RecentHistoryTypes,
        pl.RelatedPostId as DuplicateOfQuestionId,
        pl2.Title as DuplicateOfTitle
    from QuestionsWithCommentCount q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3 -- duplicate links
    left join Posts pl2 on pl.RelatedPostId = pl2.Id
    where q.CloseReasonName is not null
)
select
    cq.Id as QuestionId,
    cq.Title,
    coalesce(cq.DisplayName, 'Community') as OwnerDisplayName,
    cq.CreationDate,
    cq.Score,
    cq.ViewCount,
    cq.UpVotes,
    cq.DownVotes,
    cq.FavoriteCount,
    cq.HighScoreAnswers,
    round(cq.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    cq.MaxAnswerScore,
    cq.GoldBadges,
    cq.SilverBadges,
    cq.BronzeBadges,
    cq.CloseReasonName,
    to_char(cq.CloseDate, 'YYYY-MM-DD') as CloseDate,
    cq.RankWithinCloseReason,
    cq.CommentCount,
    array_to_string(cq.RecentHistoryTypes, ', ') as RecentHistoryTypes,
    cq.DuplicateOfQuestionId,
    cq.DuplicateOfTitle,
    -- Complex string and NULL logic expression:
    case
        when cq.DuplicateOfQuestionId is not null then
            '❌ Duplicate of [' || coalesce(cq.DuplicateOfTitle, 'unknown title') || '](post/' || cq.DuplicateOfQuestionId || ')'
        when cq.CloseReasonName = 'Off-topic' then
            '⚠️ Off-topic: Requires attention'
        when cq.CloseReasonName is not null then
            'Closed (' || cq.CloseReasonName || ')'
        else
            'Open'
    end as StatusDescription,
    -- Window function with NULL handling and math:
    round(
        percentile_cont(0.75) within group (order by coalesce(Score,0))
        over (partition by coalesce(CloseReasonName,'OPEN'))
        ,2) as Score75thPercentileByCloseReason
from ClosedQuestionsAndDuplicates cq
where cq.RankWithinCloseReason <= 20
order by coalesce(cq.CloseReasonName,'OPEN'), cq.RankWithinCloseReason
limit 100;