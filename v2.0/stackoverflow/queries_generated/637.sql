-- {"query": "637.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3042} 
with params as (
    select
        cast(365 as int) as lookback_days,
        cast(10 as int) as min_answers,
        cast(50 as int) as min_views,
        cast(100 as int) as min_rep
),
recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.Title,
        q.Tags,
        coalesce(q.AnswerCount, 0) as AnswerCount
    from Posts q
    cross join params p
    where q.PostTypeId = 1
      and q.CreationDate >= now() - (p.lookback_days || ' days')::interval
      and coalesce(q.ViewCount, 0) >= p.min_views
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        a.CommentCount as AnswerCommentCount
    from Posts a
    where a.PostTypeId = 2
),
q_answer_stats as (
    select
        r.QuestionId,
        count(a.AnswerId) as total_answers,
        sum(case when a.AnswerScore > 0 then 1 else 0 end) as pos_answers,
        max(a.AnswerScore) as max_answer_score,
        min(a.AnswerScore) as min_answer_score,
        avg(a.AnswerScore::numeric) as avg_answer_score,
        count(distinct a.OwnerUserId) filter (where a.OwnerUserId is not null) as distinct_answerers
    from recent_questions r
    left join answers a on a.QuestionId = r.QuestionId
    group by r.QuestionId
),
accepted_answerers as (
    select
        r.QuestionId,
        a.OwnerUserId as AcceptedOwnerUserId
    from recent_questions r
    left join Posts a on a.Id = r.AcceptedAnswerId
),
user_aug as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.UpVotes,
        u.DownVotes,
        (u.UpVotes - u.DownVotes) as NetVotes,
        case
            when u.Location is null or btrim(u.Location) = '' then '(unknown)'
            else u.Location
        end as NormLocation
    from Users u
),
questioner as (
    select
        r.QuestionId,
        u.UserId as QuestionOwnerId,
        u.DisplayName as QuestionOwnerName,
        u.Reputation as QuestionOwnerRep,
        u.NormLocation as QuestionOwnerLocation,
        u.NetVotes as QuestionOwnerNetVotes
    from recent_questions r
    left join user_aug u on u.UserId = r.OwnerUserId
),
answerer_agg as (
    select
        r.QuestionId,
        count(distinct a.OwnerUserId) as distinct_answerers,
        sum(u.Reputation) filter (where a.OwnerUserId = u.UserId) as sum_answerer_rep,
        avg(u.Reputation::numeric) filter (where a.OwnerUserId = u.UserId) as avg_answerer_rep,
        max(u.Reputation) filter (where a.OwnerUserId = u.UserId) as max_answerer_rep
    from recent_questions r
    left join answers a on a.QuestionId = r.QuestionId
    left join user_aug u on u.UserId = a.OwnerUserId
    group by r.QuestionId
),
comments_on_q as (
    select
        c.PostId as QuestionId,
        count(*) as q_comment_count,
        sum(c.Score) as q_comment_score_sum,
        max(c.Score) as q_comment_score_max
    from Comments c
    join recent_questions r on r.QuestionId = c.PostId
    group by c.PostId
),
votes_on_q as (
    select
        v.PostId as QuestionId,
        count(*) filter (where v.VoteTypeId = 2) as upvotes,
        count(*) filter (where v.VoteTypeId = 3) as downvotes,
        count(*) filter (where v.VoteTypeId = 5) as favorites,
        count(*) filter (where v.VoteTypeId in (8,9)) as bounty_votes,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as bounty_amount
    from Votes v
    join recent_questions r on r.QuestionId = v.PostId
    group by v.PostId
),
closures as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) as first_closed_at,
        max(ph.CreationDate) as last_closed_at,
        count(*) as close_events,
        string_agg(distinct crt.Name, ',') as reasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    join recent_questions r on r.QuestionId = ph.PostId
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
duplicates as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as duplicate_links,
        count(*) filter (where pl.LinkTypeId = 1) as linked_links
    from PostLinks pl
    join recent_questions r on r.QuestionId = pl.PostId
    group by pl.PostId
),
tag_expansion as (
    select
        r.QuestionId,
        unnest(string_to_array(substring(r.Tags, 2, greatest(length(r.Tags)-2,0)), '><')) as tagname
    from recent_questions r
    where r.Tags is not null and length(r.Tags) >= 2
),
tag_stats as (
    select
        te.QuestionId,
        count(*) as tag_count,
        sum(t.Count) as sum_tag_popularity,
        max(t.Count) as max_tag_popularity,
        count(*) filter (where t.IsModeratorOnly) as mod_only_tags
    from tag_expansion te
    left join Tags t on lower(t.TagName) = lower(te.tagname)
    group by te.QuestionId
),
edits as (
    select
        ph.PostId as QuestionId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as edit_events,
        count(*) filter (where ph.PostHistoryTypeId = 24) as suggested_edits,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as first_edit_at,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as last_edit_at
    from PostHistory ph
    join recent_questions r on r.QuestionId = ph.PostId
    group by ph.PostId
),
question_activity as (
    select
        r.QuestionId,
        r.CreationDate,
        r.LastActivityDate,
        extract(epoch from (coalesce(r.LastActivityDate, now()) - r.CreationDate))::bigint as lifetime_seconds
    from recent_questions r
),
rankings as (
    select
        r.QuestionId,
        row_number() over (order by r.Score desc nulls last, r.ViewCount desc nulls last, r.CreationDate desc) as rn_score_view,
        row_number() over (order by coalesce(v.upvotes,0) - coalesce(v.downvotes,0) desc, r.CreationDate desc) as rn_vote_delta,
        dense_rank() over (order by coalesce(qs.total_answers,0) desc, r.CreationDate desc) as dr_answers,
        ntile(4) over (order by r.ViewCount desc) as view_quartile
    from recent_questions r
    left join votes_on_q v on v.QuestionId = r.QuestionId
    left join q_answer_stats qs on qs.QuestionId = r.QuestionId
),
user_quality as (
    select
        qa.QuestionId,
        case when coalesce(qo.QuestionOwnerRep,0) >= p.min_rep then 1 else 0 end as high_rep_owner,
        case when qo.QuestionOwnerNetVotes > 0 then 1 else 0 end as positive_owner_netvotes
    from questioner qo
    join q_answer_stats qa on qa.QuestionId = qo.QuestionId
    cross join params p
),
filtered as (
    select
        r.QuestionId
    from recent_questions r
    left join q_answer_stats qa on qa.QuestionId = r.QuestionId
    left join closures c on c.QuestionId = r.QuestionId
    cross join params p
    where coalesce(qa.total_answers,0) >= p.min_answers
      and (c.first_closed_at is null or c.first_closed_at > r.CreationDate + interval '1 hour')
),
final as (
    select
        r.QuestionId,
        r.Title,
        r.Tags,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        coalesce(qa.total_answers,0) as total_answers,
        qa.pos_answers,
        qa.max_answer_score,
        qa.min_answer_score,
        qa.avg_answer_score,
        aa.distinct_answerers as distinct_answerers_count,
        aa.sum_answerer_rep,
        aa.avg_answerer_rep,
        aa.max_answerer_rep,
        v.upvotes,
        v.downvotes,
        v.favorites,
        v.bounty_votes,
        v.bounty_amount,
        c.first_closed_at,
        c.last_closed_at,
        c.close_events,
        c.reasons as close_reasons,
        d.duplicate_links,
        d.linked_links,
        ts.tag_count,
        ts.sum_tag_popularity,
        ts.max_tag_popularity,
        ts.mod_only_tags,
        e.edit_events,
        e.suggested_edits,
        e.first_edit_at,
        e.last_edit_at,
        qa.distinct_answerers,
        qact.lifetime_seconds,
        qn.QuestionOwnerId,
        qn.QuestionOwnerName,
        qn.QuestionOwnerRep,
        qn.QuestionOwnerLocation,
        qn.QuestionOwnerNetVotes,
        ua.AcceptedOwnerUserId,
        rq.rn_score_view,
        rq.rn_vote_delta,
        rq.dr_answers,
        rq.view_quartile,
        uq.high_rep_owner,
        uq.positive_owner_netvotes,
        coalesce(qa.total_answers,0) * greatest(1, coalesce(v.upvotes,0) - coalesce(v.downvotes,0))::int
            + coalesce(ts.sum_tag_popularity,0)::int / greatest(1, ts.tag_count)
            + coalesce(aa.avg_answerer_rep,0)::int / 10
            + case when ua.AcceptedOwnerUserId is not null then 25 else 0 end
            - coalesce(d.duplicate_links,0) * 5
            - case when c.first_closed_at is not null then 50 else 0 end
            as perf_score
    from filtered f
    join recent_questions r on r.QuestionId = f.QuestionId
    left join q_answer_stats qa on qa.QuestionId = r.QuestionId
    left join votes_on_q v on v.QuestionId = r.QuestionId
    left join closures c on c.QuestionId = r.QuestionId
    left join duplicates d on d.QuestionId = r.QuestionId
    left join tag_stats ts on ts.QuestionId = r.QuestionId
    left join edits e on e.QuestionId = r.QuestionId
    left join question_activity qact on qact.QuestionId = r.QuestionId
    left join questioner qn on qn.QuestionId = r.QuestionId
    left join accepted_answerers ua on ua.QuestionId = r.QuestionId
    left join answerer_agg aa on aa.QuestionId = r.QuestionId
    left join rankings rq on rq.QuestionId = r.QuestionId
    left join user_quality uq on uq.QuestionId = r.QuestionId
),
dedup as (
    select
        *,
        row_number() over (partition by lower(coalesce(Title,'')) order by perf_score desc, CreationDate desc) as rn_title
    from final
),
topk as (
    select *
    from dedup
    where rn_title = 1
)
select
    t.QuestionId,
    t.Title,
    t.Tags,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    t.total_answers,
    t.pos_answers,
    t.max_answer_score,
    t.min_answer_score,
    round(t.avg_answer_score::numeric, 2) as avg_answer_score,
    t.distinct_answerers_count,
    t.sum_answerer_rep,
    t.avg_answerer_rep,
    t.max_answerer_rep,
    t.upvotes,
    t.downvotes,
    coalesce(t.upvotes,0) - coalesce(t.downvotes,0) as vote_delta,
    t.favorites,
    t.bounty_votes,
    t.bounty_amount,
    t.first_closed_at,
    t.last_closed_at,
    t.close_events,
    t.close_reasons,
    t.duplicate_links,
    t.linked_links,
    t.tag_count,
    t.sum_tag_popularity,
    t.max_tag_popularity,
    t.mod_only_tags,
    t.edit_events,
    t.suggested_edits,
    t.first_edit_at,
    t.last_edit_at,
    t.lifetime_seconds,
    t.QuestionOwnerId,
    t.QuestionOwnerName,
    t.QuestionOwnerRep,
    t.QuestionOwnerLocation,
    t.QuestionOwnerNetVotes,
    t.AcceptedOwnerUserId,
    t.rn_score_view,
    t.rn_vote_delta,
    t.dr_answers,
    t.view_quartile,
    t.high_rep_owner,
    t.positive_owner_netvotes,
    t.perf_score,
    case
        when t.Close_Events > 0 then 'Closed'
        when t.AcceptedOwnerUserId is not null then 'Accepted'
        when t.bounty_amount > 0 then 'Bounty'
        else 'Open'
    end as status_bucket
from topk t
qualify row_number() over (
    order by perf_score desc, vote_delta desc, total_answers desc, ViewCount desc, CreationDate desc
) <= 200;