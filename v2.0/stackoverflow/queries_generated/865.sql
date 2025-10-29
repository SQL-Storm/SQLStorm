-- {"query": "865.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3584} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
        date_trunc('month', u.creationdate) as signup_month,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc_rep
    from users u
    where u.creationdate >= now() - interval '5 years'
),
badge_rollup as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_core as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.favoritecount,
        p.answercount,
        p.closeddate,
        p.communityowneddate,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= now() - interval '5 years'
),
answer_core as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as a_created,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
),
q_votes as (
    select
        v.postid as question_id,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount
    from votes v
    join question_core q on q.question_id = v.postid
    group by v.postid
),
a_votes as (
    select
        v.postid as answer_id,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes
    from votes v
    join answer_core a on a.answer_id = v.postid
    group by v.postid
),
links_dupes as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
history_flags as (
    select
        ph.postid as question_id,
        max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
        max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid in (33,34) then 1 else 0 end) as had_notice,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events,
        max(ph.creationdate) as last_hist_date
    from posthistory ph
    group by ph.postid
),
comments_agg as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        min(c.creationdate) as first_comment_date,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
answers_enriched as (
    select
        a.answer_id,
        a.question_id,
        a.answerer_id,
        a.a_created,
        a.a_score,
        coalesce(av.upvotes,0) as a_up,
        coalesce(av.downvotes,0) as a_down,
        a.a_score - coalesce(av.downvotes,0) + coalesce(av.upvotes,0) as a_score_adjusted,
        row_number() over (partition by a.question_id order by a.a_score desc, a.a_created) as rn_by_score,
        row_number() over (partition by a.question_id order by a.a_created) as rn_by_time
    from answer_core a
    left join a_votes av on av.answer_id = a.answer_id
),
best_answers as (
    select
        ae.question_id,
        ae.answer_id as top_scored_answer_id,
        ae.answerer_id as top_scored_answerer_id,
        ae.a_score as top_a_score,
        ae.a_created as top_a_created
    from answers_enriched ae
    where ae.rn_by_score = 1
),
fastest_answers as (
    select
        ae.question_id,
        ae.answer_id as first_answer_id,
        ae.answerer_id as first_answerer_id,
        ae.a_created as first_a_created
    from answers_enriched ae
    where ae.rn_by_time = 1
),
accepts as (
    select
        q.question_id,
        q.acceptedanswerid as accepted_answer_id
    from question_core q
    where q.acceptedanswerid is not null
),
q_tag_expanded as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from question_core q
    where q.tags is not null and length(q.tags) >= 2
),
tag_focus as (
    select
        t.tag,
        count(*) as tag_questions,
        percentile_cont(0.5) within group (order by qc.viewcount) as median_views
    from q_tag_expanded t
    join question_core qc on qc.question_id = t.question_id
    group by t.tag
    having count(*) >= 50
),
user_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(p.score) as total_post_score,
        max(p.lastactivitydate) as last_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
question_enriched as (
    select
        q.*,
        coalesce(qv.upvotes,0) as q_up,
        coalesce(qv.downvotes,0) as q_down,
        coalesce(qv.bounties_started,0) as bounties_started,
        coalesce(qv.bounty_amount,0) as bounty_amount,
        coalesce(ld.dup_count,0) as dup_count,
        coalesce(ld.linked_count,0) as linked_count,
        ld.last_link_date,
        coalesce(h.was_closed,0) as was_closed,
        coalesce(h.was_reopened,0) as was_reopened,
        coalesce(h.had_notice,0) as had_notice,
        coalesce(h.edit_events,0) as edit_events,
        h.last_hist_date,
        ca.comment_count as q_comment_count,
        ca.max_comment_score as q_max_comment_score,
        ca.first_comment_date as q_first_comment_date,
        ca.last_comment_date as q_last_comment_date
    from question_core q
    left join q_votes qv on qv.question_id = q.question_id
    left join links_dupes ld on ld.question_id = q.question_id
    left join history_flags h on h.question_id = q.question_id
    left join comments_agg ca on ca.post_id = q.question_id
),
answerers as (
    select
        ae.question_id,
        ae.answer_id,
        u.id as user_id,
        u.displayname,
        ua.a_count as total_answers_by_user,
        ua.q_count as total_questions_by_user,
        br.total_badges,
        br.gold_cnt,
        br.silver_cnt,
        br.bronze_cnt,
        coalesce(br.last_badge_date, u.creationdate) as last_award_date
    from answers_enriched ae
    left join users u on u.id = ae.answerer_id
    left join user_activity ua on ua.user_id = u.id
    left join badge_rollup br on br.userid = u.id
),
q_accepted_join as (
    select
        qe.*,
        case when ac.accepted_answer_id is not null then 1 else 0 end as has_accepted,
        ac.accepted_answer_id
    from question_enriched qe
    left join accepts ac on ac.question_id = qe.question_id
),
engagement as (
    select
        q.question_id,
        q.q_created,
        q.viewcount,
        q.q_comment_count,
        q.answercount,
        q.favoritecount,
        case
            when q.viewcount is null or q.answercount is null or q.answercount = 0 then null
            else (q.viewcount::numeric / greatest(q.answercount,1))::numeric
        end as views_per_answer,
        case
            when q.q_comment_count is null or q.q_comment_count = 0 then null
            else (q.viewcount::numeric / q.q_comment_count)::numeric
        end as views_per_comment
    from q_accepted_join q
),
ranked_questions as (
    select
        q.*,
        ba.top_scored_answer_id,
        ba.top_scored_answerer_id,
        fa.first_answer_id,
        fa.first_answerer_id,
        dense_rank() over (order by coalesce(q.q_up - q.q_down, q.q_score) desc nulls last, q.viewcount desc nulls last) as dr_popularity,
        ntile(10) over (order by coalesce(q.q_up - q.q_down, q.q_score) desc nulls last) as decile_score,
        sum(coalesce(q.q_up,0)) over (partition by date_trunc('month', q.q_created)) as monthly_upvotes_sum,
        avg(coalesce(q.viewcount,0)) over (partition by date_trunc('month', q.q_created)) as monthly_avg_views
    from q_accepted_join q
    left join best_answers ba on ba.question_id = q.question_id
    left join fastest_answers fa on fa.question_id = q.question_id
),
user_quality as (
    select
        au.user_id,
        avg(ae.a_score) as avg_answer_score,
        percentile_cont(0.9) within group (order by ae.a_score) as p90_answer_score,
        count(*) as answer_count_window
    from answers_enriched ae
    join answerers au on au.user_id = ae.answerer_id
    group by au.user_id
),
final_scored as (
    select
        rq.question_id,
        rq.asker_id,
        rq.title,
        rq.q_created,
        rq.viewcount,
        rq.q_up,
        rq.q_down,
        rq.q_score,
        rq.bounty_amount,
        rq.dup_count,
        rq.edit_events,
        rq.had_notice,
        rq.was_closed,
        rq.was_reopened,
        rq.has_accepted,
        rq.accepted_answer_id,
        rq.top_scored_answer_id,
        rq.top_scored_answerer_id,
        rq.first_answer_id,
        rq.first_answerer_id,
        rq.decile_score,
        rq.dr_popularity,
        e.views_per_answer,
        e.views_per_comment,
        coalesce(uq.avg_answer_score, 0) as top_answerer_avg_score,
        coalesce(uq.p90_answer_score, 0) as top_answerer_p90_score,
        coalesce(br.total_badges, 0) as asker_total_badges,
        r.reputation as asker_rep,
        case
            when rq.has_accepted = 1 and rq.accepted_answer_id = rq.top_scored_answer_id then 1
            when rq.has_accepted = 1 and rq.accepted_answer_id is distinct from rq.top_scored_answer_id then 0
            else null
        end as accepted_equals_top,
        case
            when rq.viewcount is null then null
            when rq.viewcount >= 100000 then 'Ultra'
            when rq.viewcount >= 20000 then 'High'
            when rq.viewcount >= 5000 then 'Medium'
            when rq.viewcount >= 1000 then 'Low'
            else 'VeryLow'
        end as popularity_bucket
    from ranked_questions rq
    left join engagement e on e.question_id = rq.question_id
    left join users r on r.id = rq.asker_id
    left join badge_rollup br on br.userid = rq.asker_id
    left join user_quality uq on uq.user_id = rq.top_scored_answerer_id
),
null_logic_test as (
    select
        f.*,
        case
            when coalesce(f.q_up,0) - coalesce(f.q_down,0) is null then 'N/A'
            when coalesce(f.q_up,0) - coalesce(f.q_down,0) > 0 then 'NetPositive'
            when coalesce(f.q_up,0) - coalesce(f.q_down,0) < 0 then 'NetNegative'
            else 'Neutral'
        end as net_vote_class,
        greatest(coalesce(f.q_up,0) - coalesce(f.q_down,0), f.q_score, 0) as effective_score,
        least(coalesce(f.viewcount, 9223372036854775807), 1000000) as capped_views,
        nullif(trim(coalesce((select min(tag) from q_tag_expanded qt where qt.question_id = f.question_id), '')), '') as first_tag
    from final_scored f
),
set_ops as (
    select question_id, 'accepted' as flag from final_scored where has_accepted = 1
    union
    select question_id, 'top_equals_accepted' as flag from final_scored where accepted_equals_top = 1
    union all
    select question_id, 'high_pop' as flag from final_scored where popularity_bucket in ('Ultra','High')
),
windowed as (
    select
        nlt.*,
        count(*) over () as total_rows,
        sum(case when so.flag = 'accepted' then 1 else 0 end) over () as accepted_rows,
        count(*) filter (where so.flag = 'top_equals_accepted') over () as top_eq_rows,
        row_number() over (order by nlt.effective_score desc, nlt.viewcount desc nulls last, nlt.q_created desc) as rn_global,
        row_number() over (partition by nlt.popularity_bucket order by nlt.effective_score desc, nlt.viewcount desc nulls last) as rn_bucket
    from null_logic_test nlt
    left join set_ops so on so.question_id = nlt.question_id
)
select
    w.question_id,
    w.asker_id,
    w.title,
    w.q_created,
    w.viewcount,
    w.q_up,
    w.q_down,
    w.q_score,
    w.effective_score,
    w.popularity_bucket,
    w.has_accepted,
    w.accepted_equals_top,
    w.top_scored_answer_id,
    w.first_answer_id,
    w.net_vote_class,
    w.first_tag,
    w.decile_score,
    w.dr_popularity,
    w.total_rows,
    w.accepted_rows,
    w.top_eq_rows,
    w.rn_global,
    w.rn_bucket
from windowed w
where (
    w.popularity_bucket in ('Ultra','High')
    or (w.effective_score >= 10 and coalesce(w.first_tag,'') <> '')
    or (w.has_accepted = 1 and w.accepted_equals_top = 0 and w.viewcount >= 1000)
)
and (
    w.q_created >= now() - interval '3 years'
    or (w.q_created >= now() - interval '5 years' and w.decile_score >= 8)
)
and not exists (
    select 1
    from comments c
    where c.postid = w.question_id
      and c.text ilike any (array['%homework%','%plz help%','%do my%'])
)
order by w.rn_global
limit 500;