-- {"query": "2091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1205} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc nulls last) as TagRank
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join Users u on p.OwnerUserId = u.Id
    where t.IsModeratorOnly = 0
),
QualifiedTags as (
    select *
    from RecursiveTagCounts
    where TagRank <= 5
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        count(case when v.VoteTypeId = 6 then 1 end) as CloseVotes,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(distinct ph.PostId) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
TopCommentersPerQuestion as (
    select
        c.PostId,
        c.UserId,
        count(*) as CommentCount,
        row_number() over (partition by c.PostId order by count(*) desc) as CommentRank
    from Comments c
    group by c.PostId, c.UserId
),
QuestionDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        pva.UpVotes,
        pva.DownVotes,
        pva.CloseVotes,
        coalesce(u.DisplayName, '<anon>') as OwnerDisplayName,
        coalesce(ubs.GoldBadges, 0) as OwnerGoldBadges,
        coalesce(ubs.SilverBadges, 0) as OwnerSilverBadges,
        coalesce(ubs.BronzeBadges, 0) as OwnerBronzeBadges,
        trc.TagName,
        trc.Count as TagGlobalCount,
        trc.TagRank,
        tc.CommentCount as TopCommenterCount,
        u2.DisplayName as TopCommenterName,
        cr.CloseCount,
        cr.CloseReason
    from Posts q
    left join PostVoteAggregates pva on q.Id = pva.PostId
    left join Users u on q.OwnerUserId = u.Id
    left join UserBadgeSummary ubs on u.Id = ubs.UserId
    left join QualifiedTags trc on q.Id = trc.QuestionId
    left join TopCommentersPerQuestion tc on q.Id = tc.PostId and tc.CommentRank = 1
    left join Users u2 on tc.UserId = u2.Id
    left join Lateral (
        select cr2.CloseReason, cr2.CloseCount
        from CloseReasonCounts cr2
        where cr2.CloseReason is not null
        order by cr2.CloseCount desc
        limit 1
    ) cr on true
    where q.PostTypeId = 1
)
select 
    qd.QuestionId,
    qd.Title,
    qd.OwnerDisplayName,
    qd.OwnerGoldBadges,
    qd.OwnerSilverBadges,
    qd.OwnerBronzeBadges,
    qd.QuestionScore,
    qd.UpVotes,
    qd.DownVotes,
    qd.CloseVotes,
    qd.TagName,
    qd.TagGlobalCount,
    qd.TagRank,
    coalesce(qd.TopCommenterName, '<no comments>') as TopCommenterName,
    qd.TopCommenterCount,
    qd.CloseReason,
    qd.CloseCount,
    case 
        when qd.CloseVotes > 0 then 'Likely Closed' 
        when qd.UpVotes > 10 then 'Popular' 
        else 'Normal' 
    end as QuestionStatus,
    length(qd.Title) + (qd.QuestionScore * 2) - coalesce(qd.TopCommenterCount, 0) as CustomScore,
    -- Example of correlated subquery for each question: count of answers
    (select count(*) from Posts a where a.ParentId = qd.QuestionId and a.PostTypeId = 2) as AnswerCount,
    -- String concatenation and NULL logic example
    concat(coalesce(qd.TagName, 'NoTag'), ' [', qd.QuestionScore, ']') as TagScoreLabel
from QuestionDetails qd
where qd.TagRank <= 3 or qd.QuestionScore > 50
order by qd.QuestionScore desc nulls last, qd.TagRank, qd.TopCommenterCount desc
limit 100;