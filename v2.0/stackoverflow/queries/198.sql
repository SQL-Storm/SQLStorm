-- {"query": "198.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3128}
with recent_questions as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        coalesce(q.AnswerCount, 0) as AnswerCount
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (
        select date_trunc('month', max(CreationDate)) - interval '6 months'
        from Posts where PostTypeId = 1
      )
),
answerers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_best_by_score
    from Posts a
    where a.PostTypeId = 2
      and a.ParentId in (select QuestionId from recent_questions)
),
accepted as (
    select
        q.QuestionId,
        p.AcceptedAnswerId
    from recent_questions q
    join Posts p on p.Id = q.QuestionId
    where p.AcceptedAnswerId is not null
),
comment_stats as (
    select
        c.PostId,
        count(case when c.Score > 0 then 1 end) as pos_comments,
        count(case when c.Score <= 0 or c.Score is null then 1 end) as nonpos_comments,
        max(c.CreationDate) as last_comment_at,
        sum(length(coalesce(c.Text, ''))) as total_comment_text_len
    from Comments c
    group by c.PostId
),
vote_stats as (
    select
        v.PostId,
        count(case when v.VoteTypeId = 2 then 1 end) as upvotes,
        count(case when v.VoteTypeId = 3 then 1 end) as downvotes,
        count(case when v.VoteTypeId = 5 then 1 end) as favorites,
        count(case when v.VoteTypeId = 8 then 1 end) as bounties_started,
        count(case when v.VoteTypeId = 9 then 1 end) as bounties_closed,
        sum(coalesce(v.BountyAmount,0)) as total_bounty
    from Votes v
    group by v.PostId
),
link_dupes as (
    select
        pl.PostId,
        count(case when pl.LinkTypeId = 3 then 1 end) as duplicate_links,
        count(case when pl.LinkTypeId = 1 then 1 end) as linked_links,
        max(pl.CreationDate) as last_link_at
    from PostLinks pl
    group by pl.PostId
),
tag_expanded as (
    select
        rq.QuestionId,
        unnest(string_to_array(substring(coalesce(rq.Tags,''), 2, greatest(length(coalesce(rq.Tags,'')) - 2, 0)), '><')) as tag
    from recent_questions rq
),
tag_metrics as (
    select
        te.QuestionId,
        array_agg(te.tag order by te.tag) as tag_list,
        count(*) as tag_count,
        sum(t.Count) as tag_popularity_sum,
        avg(cast(t.Count as numeric)) as tag_popularity_avg
    from tag_expanded te
    left join Tags t on lower(t.TagName) = lower(te.tag)
    group by te.QuestionId
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        u.LastAccessDate,
        coalesce(nullif(b.gold_badges_text, ''), '0')::integer * 1 as gold_badges,
        coalesce(nullif(b.silver_badges_text, ''), '0')::integer * 1 as silver_badges,
        coalesce(nullif(b.bronze_badges_text, ''), '0')::integer * 1 as bronze_badges
    from Users u
    left join (
        select
            UserId,
            cast(count(case when Class = 1 then 1 end) as text) as gold_badges_text,
            cast(count(case when Class = 2 then 1 end) as text) as silver_badges_text,
            cast(count(case when Class = 3 then 1 end) as text) as bronze_badges_text
        from Badges
        group by UserId
    ) b on b.UserId = u.Id
),
question_edit_events as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId in (4,5,6,7,8,9) then 1 end) as edit_events,
        count(case when ph.PostHistoryTypeId in (10) then 1 end) as closed_events,
        count(case when ph.PostHistoryTypeId in (11) then 1 end) as reopened_events,
        count(case when ph.PostHistoryTypeId in (12) then 1 end) as deleted_events,
        count(case when ph.PostHistoryTypeId in (13) then 1 end) as undeleted_events,
        max(ph.CreationDate) as last_history_at,
        bool_or(ph.PostHistoryTypeId = 19) as was_protected
    from PostHistory ph
    where ph.PostId in (select QuestionId from recent_questions)
    group by ph.PostId
),
best_answer as (
    select
        a.QuestionId,
        a.AnswerId as BestAnswerId,
        a.AnswerUserId as BestAnswerUserId,
        a.AnswerScore as BestAnswerScore,
        a.AnswerCreationDate as BestAnswerCreationDate
    from answerers a
    where a.rn_best_by_score = 1
),
accepted_flags as (
    select
        rq.QuestionId,
        case when exists (
            select 1
            from accepted acc
            join Posts aa on aa.Id = acc.AcceptedAnswerId
            where acc.QuestionId = rq.QuestionId
              and aa.Score >= 0
        ) then 1 else 0 end as has_nonneg_accepted,
        case when exists (
            select 1
            from accepted acc
            join Posts aa on aa.Id = acc.AcceptedAnswerId
            where acc.QuestionId = rq.QuestionId
        ) then 1 else 0 end as has_any_accepted
    from recent_questions rq
),
answerer_user_rollup as (
    select
        a.QuestionId,
        count(distinct a.AnswerUserId) as distinct_answerers,
        avg(cast(ua.Reputation as numeric)) as avg_answerer_rep,
        max(ua.Reputation) as max_answerer_rep,
        sum(coalesce(ua.gold_badges,0) + coalesce(ua.silver_badges,0) + coalesce(ua.bronze_badges,0)) as total_answerer_badges
    from answerers a
    left join user_activity ua on ua.UserId = a.AnswerUserId
    group by a.QuestionId
),
questioner as (
    select
        rq.QuestionId,
        ua.UserId as OwnerUserId,
        ua.Reputation as OwnerReputation,
        ua.UpVotes as OwnerUpVotes,
        ua.DownVotes as OwnerDownVotes,
        extract(epoch from (ua.LastAccessDate - ua.UserCreationDate)) / 86400.0 as owner_account_age_days
    from recent_questions rq
    left join user_activity ua on ua.UserId = rq.OwnerUserId
),
scored as (
    select
        rq.QuestionId,
        rq.Title,
        rq.Score,
        rq.ViewCount,
        rq.CreationDate,
        rq.AnswerCount,
        tm.tag_list,
        tm.tag_count,
        tm.tag_popularity_sum,
        tm.tag_popularity_avg,
        coalesce(cs.pos_comments,0) as pos_comments,
        coalesce(cs.nonpos_comments,0) as nonpos_comments,
        cs.last_comment_at,
        coalesce(vs.upvotes,0) as upvotes,
        coalesce(vs.downvotes,0) as downvotes,
        coalesce(vs.favorites,0) as favorites,
        coalesce(vs.total_bounty,0) as total_bounty,
        coalesce(ld.duplicate_links,0) as duplicate_links,
        coalesce(ld.linked_links,0) as linked_links,
        ld.last_link_at,
        coalesce(qe.edit_events,0) as edit_events,
        coalesce(qe.closed_events,0) as closed_events,
        coalesce(qe.reopened_events,0) as reopened_events,
        coalesce(qe.deleted_events,0) as deleted_events,
        coalesce(qe.undeleted_events,0) as undeleted_events,
        qe.was_protected,
        qe.last_history_at,
        qn.OwnerUserId,
        qn.OwnerReputation,
        qn.OwnerUpVotes,
        qn.OwnerDownVotes,
        qn.owner_account_age_days,
        af.has_any_accepted,
        af.has_nonneg_accepted,
        ba.BestAnswerId,
        ba.BestAnswerUserId,
        coalesce(ba.BestAnswerScore, -2147483648) as BestAnswerScore,
        aur.distinct_answerers,
        aur.avg_answerer_rep,
        aur.max_answerer_rep,
        aur.total_answerer_badges,
        (
            coalesce(rq.Score,0) * 2
            + coalesce(vs.upvotes,0) * 1.5
            - coalesce(vs.downvotes,0) * 1.0
            + ln(greatest(coalesce(rq.ViewCount,0) + 1, 1))
            + coalesce(cs.pos_comments,0) * 0.25
            + coalesce(cs.nonpos_comments,0) * 0.1
            + case when af.has_any_accepted = 1 then 5 else 0 end
            + case when coalesce(vs.total_bounty,0) > 0 then 3 else 0 end
            + coalesce(tm.tag_popularity_avg,0) * 0.0005
            + coalesce(aur.avg_answerer_rep,0) * 0.0002
            + case when qe.was_protected then -2 else 0 end
            - coalesce(qe.deleted_events,0) * 2
        ) as engagement_score
    from recent_questions rq
    left join tag_metrics tm on tm.QuestionId = rq.QuestionId
    left join comment_stats cs on cs.PostId = rq.QuestionId
    left join vote_stats vs on vs.PostId = rq.QuestionId
    left join link_dupes ld on ld.PostId = rq.QuestionId
    left join question_edit_events qe on qe.PostId = rq.QuestionId
    left join accepted_flags af on af.QuestionId = rq.QuestionId
    left join best_answer ba on ba.QuestionId = rq.QuestionId
    left join answerer_user_rollup aur on aur.QuestionId = rq.QuestionId
    left join questioner qn on qn.QuestionId = rq.QuestionId
),
ranked as (
    select
        s.QuestionId,
        s.Title,
        s.Score,
        s.ViewCount,
        s.CreationDate,
        s.AnswerCount,
        s.tag_list,
        s.tag_count,
        s.tag_popularity_sum,
        s.tag_popularity_avg,
        s.pos_comments,
        s.nonpos_comments,
        s.last_comment_at,
        s.upvotes,
        s.downvotes,
        s.favorites,
        s.total_bounty,
        s.duplicate_links,
        s.linked_links,
        s.last_link_at,
        s.edit_events,
        s.closed_events,
        s.reopened_events,
        s.deleted_events,
        s.undeleted_events,
        s.was_protected,
        s.last_history_at,
        s.OwnerUserId,
        s.OwnerReputation,
        s.OwnerUpVotes,
        s.OwnerDownVotes,
        s.owner_account_age_days,
        s.has_any_accepted,
        s.has_nonneg_accepted,
        s.BestAnswerId,
        s.BestAnswerUserId,
        s.BestAnswerScore,
        s.distinct_answerers,
        s.avg_answerer_rep,
        s.max_answerer_rep,
        s.total_answerer_badges,
        s.engagement_score,
        dense_rank() over (order by s.engagement_score desc, s.Score desc, s.ViewCount desc, s.CreationDate desc) as eng_rank,
        row_number() over (partition by coalesce(s.tag_list, array[]::text[]) order by s.engagement_score desc, s.CreationDate asc) as rn_within_tagset,
        (select percentile_cont(0.9) within group (order by engagement_score) from scored) as p90_engagement
    from scored s
),
title_tag_flags as (
    select
        r.QuestionId,
        case when lower(r.Title) ~ '\\b(how|why|what|where|when)\\b' then 1 else 0 end as is_interrogative,
        case when lower(r.Title) ~ '\\b(best|fastest|optimiz|improv|performance)\\b' then 1 else 0 end as is_perf_related,
        case when coalesce(array_length(r.tag_list,1),0) = 0 then 1 else 0 end as has_no_tags
    from ranked r
)
select
    r.QuestionId,
    coalesce(r.Title, '(no title)') as Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.engagement_score,
    r.eng_rank,
    r.rn_within_tagset,
    r.p90_engagement,
    r.tag_list,
    r.tag_count,
    r.tag_popularity_sum,
    r.tag_popularity_avg,
    r.upvotes, r.downvotes, r.favorites, r.total_bounty,
    r.duplicate_links, r.linked_links,
    r.edit_events, r.closed_events, r.reopened_events, r.deleted_events, r.undeleted_events,
    r.was_protected,
    r.last_comment_at, r.last_link_at, r.last_history_at,
    r.OwnerUserId, r.OwnerReputation, r.OwnerUpVotes, r.OwnerDownVotes, r.owner_account_age_days,
    r.has_any_accepted, r.has_nonneg_accepted,
    r.BestAnswerId, r.BestAnswerUserId, r.BestAnswerScore,
    r.distinct_answerers, r.avg_answerer_rep, r.max_answerer_rep, r.total_answerer_badges,
    tf.is_interrogative, tf.is_perf_related, tf.has_no_tags,
    case
        when r.engagement_score >= r.p90_engagement then 'top_10_percent'
        when r.engagement_score is null then 'no_score'
        else 'normal'
    end as engagement_bucket
from ranked r
left join title_tag_flags tf on tf.QuestionId = r.QuestionId
where (
    (r.Score >= 0 or r.Score is null)
    and (
        r.tag_count is null
        or r.tag_count between 1 and 5
        or (r.tag_list @> array['performance'] and r.ViewCount >= 100)
    )
    and (
        r.has_any_accepted = 1
        or (r.AnswerCount > 0 and coalesce(r.downvotes,0) <= coalesce(r.upvotes,0))
        or (r.AnswerCount = 0 and r.ViewCount >= 1000)
    )
    and not (coalesce(r.deleted_events,0) > 0 and coalesce(r.closed_events,0) > 0)
)
order by
    r.engagement_score desc,
    r.Score desc,
    r.ViewCount desc,
    r.CreationDate desc
limit 200;