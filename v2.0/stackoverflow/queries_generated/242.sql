-- {"query": "242.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3583} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= now() - interval '5 years'
),
active_posts as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid,
        p.lastactivitydate,
        case
            when p.posttypeid = 1 then 'Question'
            when p.posttypeid = 2 then 'Answer'
            else 'Other'
        end as post_type_name
    from posts p
    where p.creationdate >= now() - interval '5 years'
),
user_post_activity as (
    select
        ru.user_id,
        count(*) filter (where ap.posttypeid = 1) as questions_count,
        count(*) filter (where ap.posttypeid = 2) as answers_count,
        sum(ap.score) as total_post_score,
        avg(nullif(ap.viewcount, 0)) as avg_views_nonzero,
        max(ap.lastactivitydate) as last_activity,
        count(*) filter (where ap.acceptedanswerid is not null) as questions_with_accepted,
        count(*) as total_posts
    from recent_users ru
    left join active_posts ap
        on ap.owneruserid = ru.user_id
    group by ru.user_id
),
tag_exploded as (
    select
        ap.post_id,
        ap.posttypeid,
        lower(trim(tg)) as tag
    from active_posts ap
    cross join lateral unnest(
        case
            when ap.tags is null then array[]::varchar[]
            else string_to_array(substring(ap.tags, 2, greatest(length(ap.tags)-2,0)), '><')
        end
    ) as tg
),
top_user_tags as (
    select
        ap.owneruserid as user_id,
        te.tag,
        count(*) as tag_post_count,
        row_number() over (partition by ap.owneruserid order by count(*) desc, min(ap.creationdate)) as rn
    from active_posts ap
    join tag_exploded te on te.post_id = ap.id
    group by ap.owneruserid, te.tag
),
vote_summaries as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes
    from votes v
    where v.creationdate >= now() - interval '5 years'
    group by v.postid
),
comment_activity as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_date,
        sum(c.score) as comment_score_sum
    from comments c
    where c.creationdate >= now() - interval '5 years'
    group by c.postid
),
post_close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) as last_closed_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
duplicate_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links_count,
        count(*) filter (where pl.linktypeid = 1) as linked_links_count,
        min(pl.creationdate) as first_linked_at
    from postlinks pl
    group by pl.postid
),
accepted_answers as (
    select
        q.id as question_id,
        a.id as answer_id,
        a.owneruserid as answerer_id,
        a.score as answer_score,
        a.creationdate as answer_date
    from posts q
    join posts a on a.id = q.acceptedanswerid
),
user_quality_metrics as (
    select
        ru.user_id,
        coalesce(sum(vs.upvotes) filter (where ap.owneruserid = ru.user_id), 0) as received_upvotes,
        coalesce(sum(vs.downvotes) filter (where ap.owneruserid = ru.user_id), 0) as received_downvotes,
        coalesce(sum(vs.favorites) filter (where ap.owneruserid = ru.user_id), 0) as received_favorites,
        coalesce(sum(vs.total_votes) filter (where ap.owneruserid = ru.user_id), 0) as received_total_votes,
        coalesce(sum(ca.comment_count) filter (where ap.owneruserid = ru.user_id), 0) as received_comments,
        coalesce(sum(ca.comment_score_sum) filter (where ap.owneruserid = ru.user_id), 0) as received_comment_score
    from recent_users ru
    left join active_posts ap on ap.owneruserid = ru.user_id
    left join vote_summaries vs on vs.postid = ap.id
    left join comment_activity ca on ca.postid = ap.id
    group by ru.user_id
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= now() - interval '5 years'
    group by b.userid
),
question_answer_latency as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        min(a.creationdate) - q.creationdate as time_to_first_answer,
        min(a.creationdate) filter (where aa.answer_id is not null) - q.creationdate as time_to_accepted_answer
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    left join accepted_answers aa on aa.question_id = q.id
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '5 years'
    group by q.id, q.owneruserid
),
user_engagement as (
    select
        ru.user_id,
        count(distinct qa.question_id) as questions_asked,
        avg(extract(epoch from qa.time_to_first_answer)) as avg_secs_to_first_answer,
        avg(extract(epoch from qa.time_to_accepted_answer)) as avg_secs_to_accepted_answer
    from recent_users ru
    left join question_answer_latency qa on qa.asker_id = ru.user_id
    group by ru.user_id
),
post_aggregates as (
    select
        ap.id as post_id,
        ap.owneruserid as user_id,
        coalesce(vs.upvotes,0) as upvotes,
        coalesce(vs.downvotes,0) as downvotes,
        coalesce(vs.favorites,0) as favorites,
        coalesce(vs.total_votes,0) as total_votes,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.comment_score_sum,0) as comment_score_sum,
        coalesce(dl.duplicate_links_count,0) as duplicate_links_count,
        coalesce(dl.linked_links_count,0) as linked_links_count,
        pc.first_closed_at,
        pc.last_closed_at,
        pc.close_events,
        pc.reopen_events,
        pc.last_close_reason_id
    from active_posts ap
    left join vote_summaries vs on vs.postid = ap.id
    left join comment_activity ca on ca.postid = ap.id
    left join duplicate_links dl on dl.postid = ap.id
    left join post_close_events pc on pc.postid = ap.id
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        upa.questions_count,
        upa.answers_count,
        upa.total_post_score,
        uqm.received_upvotes,
        uqm.received_downvotes,
        uqm.received_favorites,
        uqm.received_total_votes,
        uqm.received_comments,
        uqm.received_comment_score,
        coalesce(br.total_badges,0) as total_badges,
        coalesce(br.gold_badges,0) as gold_badges,
        coalesce(br.silver_badges,0) as silver_badges,
        coalesce(br.bronze_badges,0) as bronze_badges,
        coalesce(br.tag_badges,0) as tag_badges,
        ue.questions_asked,
        ue.avg_secs_to_first_answer,
        ue.avg_secs_to_accepted_answer,
        t.tag as top_tag_primary,
        dense_rank() over (
            order by
                coalesce(upa.total_post_score,0) + coalesce(uqm.received_upvotes,0) * 2
                - coalesce(uqm.received_downvotes,0) desc,
                coalesce(br.total_badges,0) desc,
                ru.reputation desc
        ) as performance_rank
    from recent_users ru
    left join user_post_activity upa on upa.user_id = ru.user_id
    left join user_quality_metrics uqm on uqm.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join user_engagement ue on ue.user_id = ru.user_id
    left join top_user_tags t on t.user_id = ru.user_id and t.rn = 1
),
outlier_users as (
    select
        r.*,
        case
            when r.received_upvotes + r.received_downvotes > 0
                 and r.received_upvotes::numeric / nullif((r.received_upvotes + r.received_downvotes),0) > 0.95
            then 1 else 0 end as is_highly_upvoted,
        case
            when r.answers_count > 0 and coalesce(r.questions_count,0) = 0 then 1 else 0 end as is_answer_only,
        case
            when r.total_badges >= 10 and r.reputation < 1000 then 1 else 0 end as is_badged_low_rep
    from ranked_users r
),
post_windows as (
    select
        pa.*,
        avg(pa.upvotes - pa.downvotes) over (partition by pa.user_id) as avg_net_votes_by_user,
        percentile_cont(0.9) within group (order by coalesce(pa.comment_count,0)) over (partition by pa.user_id) as p90_comments_by_user,
        sum(pa.favorites) over (partition by pa.user_id order by pa.post_id
            rows between unbounded preceding and current row) as running_favorites_by_user
    from post_aggregates pa
),
user_summary as (
    select
        ou.user_id,
        ou.displayname,
        ou.reputation,
        ou.cohort_month,
        ou.performance_rank,
        ou.top_tag_primary,
        ou.questions_count,
        ou.answers_count,
        ou.total_post_score,
        ou.received_upvotes,
        ou.received_downvotes,
        ou.received_favorites,
        ou.received_total_votes,
        ou.received_comments,
        ou.received_comment_score,
        ou.total_badges,
        ou.gold_badges,
        ou.silver_badges,
        ou.bronze_badges,
        ou.tag_badges,
        ou.questions_asked,
        ou.avg_secs_to_first_answer,
        ou.avg_secs_to_accepted_answer,
        ou.is_highly_upvoted,
        ou.is_answer_only,
        ou.is_badged_low_rep,
        coalesce(sum(case when pw.upvotes - pw.downvotes >= pw.avg_net_votes_by_user then 1 else 0 end),0) as posts_at_or_above_avg_net_votes,
        coalesce(max(pw.p90_comments_by_user),0) as p90_comments,
        coalesce(max(pw.running_favorites_by_user),0) as running_favorites_last_post
    from outlier_users ou
    left join post_windows pw on pw.user_id = ou.user_id
    group by
        ou.user_id, ou.displayname, ou.reputation, ou.cohort_month, ou.performance_rank, ou.top_tag_primary,
        ou.questions_count, ou.answers_count, ou.total_post_score, ou.received_upvotes, ou.received_downvotes,
        ou.received_favorites, ou.received_total_votes, ou.received_comments, ou.received_comment_score,
        ou.total_badges, ou.gold_badges, ou.silver_badges, ou.bronze_badges, ou.tag_badges,
        ou.questions_asked, ou.avg_secs_to_first_answer, ou.avg_secs_to_accepted_answer,
        ou.is_highly_upvoted, ou.is_answer_only, ou.is_badged_low_rep
),
closed_reason_name as (
    select
        ph.postid,
        crt.name as close_reason_name,
        max(ph.creationdate) as reason_at
    from posthistory ph
    join closerreasontypes crt on crt.id::varchar = ph.comment
    where ph.posthistorytypeid = 10
      and ph.comment ~ '^[0-9]+$'
    group by ph.postid, crt.name
),
final_posts as (
    select
        ap.id as post_id,
        ap.owneruserid as user_id,
        ap.title,
        ap.post_type_name,
        coalesce(crn.close_reason_name, 'n/a') as last_close_reason,
        ap.score,
        ap.viewcount,
        pa.upvotes,
        pa.downvotes,
        pa.favorites,
        pa.comment_count,
        pa.duplicate_links_count,
        pa.linked_links_count
    from active_posts ap
    left join post_aggregates pa on pa.post_id = ap.id
    left join closed_reason_name crn on crn.postid = ap.id
)
select
    us.user_id,
    us.displayname,
    us.reputation,
    us.cohort_month,
    us.performance_rank,
    us.top_tag_primary,
    us.questions_count,
    us.answers_count,
    us.total_post_score,
    us.received_upvotes,
    us.received_downvotes,
    us.received_favorites,
    us.received_total_votes,
    us.received_comments,
    us.received_comment_score,
    us.total_badges,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.tag_badges,
    us.questions_asked,
    us.avg_secs_to_first_answer,
    us.avg_secs_to_accepted_answer,
    us.is_highly_upvoted,
    us.is_answer_only,
    us.is_badged_low_rep,
    fp.post_id,
    fp.title,
    fp.post_type_name,
    fp.last_close_reason,
    fp.score as post_score,
    fp.viewcount as post_views,
    fp.upvotes,
    fp.downvotes,
    fp.favorites,
    fp.comment_count,
    fp.duplicate_links_count,
    fp.linked_links_count
from user_summary us
left join final_posts fp
  on fp.user_id = us.user_id
where coalesce(us.total_post_score,0) + coalesce(us.received_upvotes,0) * 2 - coalesce(us.received_downvotes,0) >= (
    select percentile_cont(0.75) within group (order by coalesce(total_post_score,0) + coalesce(received_upvotes,0) * 2 - coalesce(received_downvotes,0))
    from user_summary
)
order by us.performance_rank, us.user_id, fp.post_id nulls last;