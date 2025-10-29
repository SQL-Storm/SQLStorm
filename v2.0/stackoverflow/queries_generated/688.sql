-- {"query": "688.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2427} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.Score,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts where PostTypeId = 1)
),
tag_expanded as (
    select
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.OwnerUserId,
        lower(trim(t)) as tag,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount
    from recent_questions rq
    left join lateral unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2, 0)), '><')) as t on true
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        sum(coalesce(votes_up.cnt_up, 0)) over (partition by u.Id) as TotalUpVotesGiven,
        sum(coalesce(votes_down.cnt_down, 0)) over (partition by u.Id) as TotalDownVotesGiven,
        count(distinct b.Id) filter (where b.Class = 1) over (partition by u.Id) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) over (partition by u.Id) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) over (partition by u.Id) as BronzeBadges
    from Users u
    left join lateral (
        select UserId, count(*) as cnt_up
        from Votes
        where VoteTypeId = 2
        group by UserId
    ) votes_up on votes_up.UserId = u.Id
    left join lateral (
        select UserId, count(*) as cnt_down
        from Votes
        where VoteTypeId = 3
        group by UserId
    ) votes_down on votes_down.UserId = u.Id
    left join Badges b on b.UserId = u.Id
),
question_metrics as (
    select
        te.QuestionId,
        te.Title,
        te.CreationDate,
        te.OwnerUserId,
        te.Score,
        te.ViewCount,
        te.AnswerCount,
        array_agg(distinct te.tag) filter (where te.tag is not null) as tags_array,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as linked_count,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as duplicate_refs,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
        avg(cast(c.Score as numeric)) as avg_comment_score,
        count(c.Id) as comment_count
    from tag_expanded te
    left join PostLinks pl on pl.PostId = te.QuestionId
    left join Votes v on v.PostId = te.QuestionId
    left join Comments c on c.PostId = te.QuestionId
    group by te.QuestionId, te.Title, te.CreationDate, te.OwnerUserId, te.Score, te.ViewCount, te.AnswerCount
),
first_answer as (
    select
        q.Id as QuestionId,
        min(a.CreationDate) as FirstAnswerDate,
        count(a.Id) as TotalAnswers
    from Posts q
    left join Posts a
        on a.ParentId = q.Id
       and a.PostTypeId = 2
    where q.PostTypeId = 1
      and q.Id in (select QuestionId from recent_questions)
    group by q.Id
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) as FirstCloseDate,
        max(ph.CreationDate) as LastCloseDate,
        count(*) as CloseEventCount,
        max(case when crt.Id is not null then crt.Name else null end) keep
            (dense_rank last order by ph.CreationDate) as LastCloseReasonName
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::varchar = nullif(ph.Comment, '')::varchar
    where ph.PostHistoryTypeId = 10
      and ph.PostId in (select QuestionId from recent_questions)
    group by ph.PostId
),
owner_rollup as (
    select
        qm.QuestionId,
        qm.Title,
        qm.CreationDate,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount,
        qm.tags_array,
        qm.linked_count,
        qm.duplicate_refs,
        qm.upvotes,
        qm.downvotes,
        qm.favorites,
        qm.avg_comment_score,
        qm.comment_count,
        fa.FirstAnswerDate,
        fa.TotalAnswers,
        ce.FirstCloseDate,
        ce.LastCloseDate,
        ce.CloseEventCount,
        ce.LastCloseReasonName,
        ua.UserId as OwnerUserId,
        ua.DisplayName as OwnerDisplayName,
        ua.Reputation as OwnerReputation,
        ua.Location as OwnerLocation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges
    from question_metrics qm
    left join first_answer fa on fa.QuestionId = qm.QuestionId
    left join close_events ce on ce.QuestionId = qm.QuestionId
    left join user_activity ua on ua.UserId = qm.OwnerUserId
),
ranked as (
    select
        o.*,
        case
            when o.ViewCount > 0 then (o.upvotes - o.downvotes)::numeric / o.ViewCount
            else null
        end as vote_view_ratio,
        case
            when o.AnswerCount > 0 then (o.TotalAnswers::numeric / o.AnswerCount)
            else null
        end as answer_ratio_check,
        extract(epoch from (coalesce(o.FirstAnswerDate, o.CreationDate) - o.CreationDate)) / 3600.0 as hours_to_first_answer,
        row_number() over (partition by coalesce(o.OwnerUserId, -1) order by coalesce(o.Score, -2147483648) desc, o.ViewCount desc) as rn_by_owner,
        dense_rank() over (order by coalesce(o.ViewCount, 0) desc) as dr_by_views,
        ntile(10) over (order by coalesce(o.Score, 0) desc) as decile_by_score
    from owner_rollup o
),
dupe_groups as (
    select
        q.QuestionId,
        count(distinct dl.RelatedPostId) as dupe_of_count,
        bool_or(p2.AcceptedAnswerId is not null) as has_dupe_with_accept
    from (select QuestionId from recent_questions) q
    left join PostLinks dl on dl.PostId = q.QuestionId and dl.LinkTypeId = 3
    left join Posts p2 on p2.Id = dl.RelatedPostId
    group by q.QuestionId
),
final_scores as (
    select
        r.*,
        dg.dupe_of_count,
        dg.has_dupe_with_accept,
        (
            coalesce(r.Score, 0) * 3
            + coalesce(r.upvotes, 0) * 2
            - coalesce(r.downvotes, 0)
            + coalesce(r.favorites, 0) * 4
            + least(coalesce(r.ViewCount, 0), 10000) / 100
            - coalesce(dg.dupe_of_count, 0) * 5
            + case when coalesce(r.LastCloseDate, r.FirstCloseDate) is not null then -20 else 0 end
            + case when coalesce(r.OwnerReputation, 0) > 10000 then 5 else 0 end
            + coalesce(r.GoldBadges, 0)
        ) as composite_score
    from ranked r
    left join dupe_groups dg on dg.QuestionId = r.QuestionId
)
select
    fs.QuestionId,
    fs.Title,
    fs.OwnerDisplayName,
    coalesce(array_to_string(fs.tags_array, ','), '') as tags_csv,
    fs.ViewCount,
    fs.Score,
    fs.upvotes,
    fs.downvotes,
    fs.favorites,
    fs.comment_count,
    round(coalesce(fs.avg_comment_score, 0)::numeric, 2) as avg_comment_score,
    round(coalesce(fs.vote_view_ratio, 0)::numeric, 6) as vote_view_ratio,
    fs.hours_to_first_answer,
    fs.FirstCloseDate,
    fs.LastCloseDate,
    fs.CloseEventCount,
    coalesce(fs.LastCloseReasonName, 'N/A') as LastCloseReasonName,
    fs.dupe_of_count,
    fs.has_dupe_with_accept,
    fs.decile_by_score,
    fs.dr_by_views,
    fs.rn_by_owner,
    fs.composite_score
from final_scores fs
where (
        fs.tags_array is null
        or not exists (
            select 1
            from unnest(fs.tags_array) t(tag)
            where tag similar to '(discussion|off-topic|fun(.*)?)'
        )
    )
  and coalesce(fs.OwnerReputation, 0) >= 1
  and coalesce(fs.ViewCount, 0) >= 0
  and (
        fs.AnswerCount is null
        or fs.TotalAnswers >= 0
    )
union all
select
    -1 as QuestionId,
    'AGGREGATE' as Title,
    null as OwnerDisplayName,
    '' as tags_csv,
    sum(fs.ViewCount) as ViewCount,
    sum(fs.Score) as Score,
    sum(fs.upvotes) as upvotes,
    sum(fs.downvotes) as downvotes,
    sum(fs.favorites) as favorites,
    sum(fs.comment_count) as comment_count,
    round(avg(coalesce(fs.avg_comment_score, 0))::numeric, 2) as avg_comment_score,
    round(avg(coalesce(fs.vote_view_ratio, 0))::numeric, 6) as vote_view_ratio,
    avg(fs.hours_to_first_answer) as hours_to_first_answer,
    min(fs.FirstCloseDate) as FirstCloseDate,
    max(fs.LastCloseDate) as LastCloseDate,
    sum(fs.CloseEventCount) as CloseEventCount,
    'N/A' as LastCloseReasonName,
    sum(fs.dupe_of_count) as dupe_of_count,
    bool_or(fs.has_dupe_with_accept) as has_dupe_with_accept,
    null as decile_by_score,
    null as dr_by_views,
    null as rn_by_owner,
    sum(fs.composite_score) as composite_score
from final_scores fs
order by
    case when QuestionId = -1 then 1 else 0 end,
    composite_score desc,
    ViewCount desc
limit 200;