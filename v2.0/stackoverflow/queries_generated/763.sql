-- {"query": "763.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3376} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from users u
    left join badges b
      on b.userid = u.id
    where u.lastaccessdate >= now() - interval '365 days'
    group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, norm_location
),
user_posts as (
    select
        p.owneruserid as user_id,
        p.posttypeid,
        count(*) as post_count,
        sum(coalesce(p.score, 0)) as total_score,
        sum(coalesce(p.viewcount, 0)) as total_views,
        avg(nullif(p.score, 0)) as avg_nonzero_score,
        max(p.creationdate) as last_post_date,
        count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as questions_with_accepted,
        count(*) filter (where p.posttypeid = 2 and p.parentid is not null) as answers_count
    from posts p
    group by p.owneruserid, p.posttypeid
),
user_post_agg as (
    select
        up.user_id,
        sum(case when up.posttypeid = 1 then up.post_count else 0 end) as question_count,
        sum(case when up.posttypeid = 2 then up.post_count else 0 end) as answer_count,
        sum(up.total_score) as user_total_score,
        sum(up.total_views) as user_total_views,
        max(up.last_post_date) as last_post_date,
        sum(up.questions_with_accepted) as questions_with_accepted,
        sum(up.answers_count) as answers_count_calc,
        avg(up.avg_nonzero_score) as avg_nonzero_score_over_types
    from user_posts up
    group by up.user_id
),
tagged_questions as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_date,
        q.score as question_score,
        q.viewcount as question_views,
        q.title,
        q.tags,
        string_to_array(substring(q.tags, 2, length(q.tags)-2), '><') as tag_array
    from posts q
    where q.posttypeid = 1
),
question_tag_expanded as (
    select
        tq.question_id,
        tq.asker_id,
        lower(trim(t)) as tag_name
    from tagged_questions tq
    cross join lateral unnest(tq.tag_array) as t
),
top_tags as (
    select
        qte.asker_id as user_id,
        qte.tag_name,
        count(*) as tag_freq,
        row_number() over (partition by qte.asker_id order by count(*) desc, qte.tag_name) as rn
    from question_tag_expanded qte
    group by qte.asker_id, qte.tag_name
),
user_top_tag as (
    select user_id, tag_name, tag_freq
    from top_tags
    where rn = 1
),
dup_closures as (
    select
        ph.postid as question_id,
        min(ph.creationdate) as first_close_date,
        count(*) as close_events
    from posthistory ph
    where ph.posthistorytypeid in (10,35) -- closed or migrated away
      and (
          ph.comment::varchar ~ '^[0-9]+$' or ph.comment is null
      )
    group by ph.postid
),
postlink_dups as (
    select
        pl.postid as dup_id,
        pl.relatedpostid as canonical_id,
        min(pl.creationdate) as first_link_date,
        count(*) as link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
accepted_answerers as (
    select
        a.owneruserid as user_id,
        q.owneruserid as asker_id,
        count(*) as accepted_answers_given,
        sum(coalesce(a.score,0)) as accepted_answer_score
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
    group by a.owneruserid, q.owneruserid
),
vote_summary as (
    select
        p.owneruserid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_rcvd,
        count(*) filter (where v.votetypeid = 3) as downvotes_rcvd,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
    from posts p
    left join votes v
      on v.postid = p.id
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        avg(coalesce(c.score,0)) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
recent_hot_questions as (
    select
        ph.postid as question_id,
        min(ph.creationdate) as first_hot_date
    from posthistory ph
    where ph.posthistorytypeid = 52
      and ph.creationdate >= now() - interval '365 days'
    group by ph.postid
),
question_engagement as (
    select
        q.id as question_id,
        count(distinct v.id) filter (where v.votetypeid in (2,3)) as vote_events,
        count(distinct c.id) as comment_events,
        coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) as net_votes
    from posts q
    left join votes v on v.postid = q.id
    left join comments c on c.postid = q.id
    where q.posttypeid = 1
    group by q.id
),
user_quality_score as (
    select
        u.id as user_id,
        coalesce(ua.user_total_score,0) as total_score,
        coalesce(ua.user_total_views,0) as total_views,
        coalesce(vs.upvotes_rcvd,0) as upvotes_rcvd,
        coalesce(vs.downvotes_rcvd,0) as downvotes_rcvd,
        coalesce(vs.bounty_total,0) as bounty_total,
        coalesce(ua.answer_count,0) as answers_count,
        coalesce(ua.question_count,0) as questions_count,
        coalesce(ua.questions_with_accepted,0) as questions_with_accepted,
        coalesce(ca.comments_made,0) as comments_made,
        coalesce(ca.avg_comment_score,0) as avg_comment_score,
        greatest(
            coalesce(ua.user_total_score,0) * 1.0
            + coalesce(vs.upvotes_rcvd,0) * 2.5
            - coalesce(vs.downvotes_rcvd,0) * 1.5
            + coalesce(vs.bounty_total,0) * 0.1
            + coalesce(ua.answers_count,0) * 1.2
            + coalesce(ua.questions_with_accepted,0) * 5.0
            + case when coalesce(ua.avg_nonzero_score_over_types,0) > 0 then 3.0 else 0 end
            + least(coalesce(ua.user_total_views,0) / 100.0, 500.0)
            + least(coalesce(ca.comments_made,0) / 10.0, 300.0),
            0
        ) as quality_score
    from users u
    left join user_post_agg ua on ua.user_id = u.id
    left join vote_summary vs on vs.user_id = u.id
    left join comment_activity ca on ca.user_id = u.id
),
user_ranked as (
    select
        rau.user_id,
        rau.displayname,
        rau.reputation,
        rau.norm_location,
        rau.gold_badges,
        rau.silver_badges,
        rau.bronze_badges,
        rau.last_badge_date,
        ua.question_count,
        ua.answer_count,
        uqs.quality_score,
        dense_rank() over (
            order by
                uqs.quality_score desc,
                rau.reputation desc,
                coalesce(rau.gold_badges,0) desc,
                coalesce(rau.silver_badges,0) desc,
                coalesce(rau.bronze_badges,0) desc,
                rau.lastaccessdate desc
        ) as quality_rank
    from recent_active_users rau
    left join user_post_agg ua on ua.user_id = rau.user_id
    left join user_quality_score uqs on uqs.user_id = rau.user_id
),
location_agg as (
    select
        norm_location,
        count(*) as users_in_location,
        avg(quality_score) as avg_quality_in_location,
        percentile_cont(0.9) within group (order by quality_score) as p90_quality_in_location
    from user_ranked
    group by norm_location
),
user_tag_mix as (
    select
        u.id as user_id,
        count(distinct lower(trim(t))) filter (where t is not null and t <> '') as distinct_tags_used
    from users u
    left join posts p on p.owneruserid = u.id and p.posttypeid = 1
    left join lateral (
        select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))
    ) t(t)
    group by u.id
),
recent_link_graph as (
    select
        pl.postid as source_id,
        pl.relatedpostid as target_id,
        pl.linktypeid,
        pl.creationdate
    from postlinks pl
    where pl.creationdate >= now() - interval '180 days'
),
question_cluster as (
    select
        q.id as question_id,
        count(*) as degree_recent_links,
        count(*) filter (where rlg.linktypeid = 3) as dup_edges_recent
    from posts q
    left join recent_link_graph rlg
      on rlg.source_id = q.id or rlg.target_id = q.id
    where q.posttypeid = 1
    group by q.id
),
final_users as (
    select
        ur.*,
        coalesce(lt.tag_name, '(none)') as top_tag,
        lt.tag_freq as top_tag_freq,
        utm.distinct_tags_used,
        la.users_in_location,
        la.avg_quality_in_location,
        la.p90_quality_in_location
    from user_ranked ur
    left join user_top_tag lt on lt.user_id = ur.user_id
    left join user_tag_mix utm on utm.user_id = ur.user_id
    left join location_agg la on la.norm_location = ur.norm_location
),
question_scores as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        qe.vote_events,
        qe.comment_events,
        qe.net_votes,
        qc.degree_recent_links,
        qc.dup_edges_recent,
        coalesce(dc.close_events,0) as close_events,
        coalesce((select sum(link_count) from postlink_dups pd where pd.dup_id = q.id), 0) as dup_link_count,
        coalesce((select min(first_link_date) from postlink_dups pd where pd.dup_id = q.id), q.creationdate) as first_dup_link_date
    from posts q
    left join question_engagement qe on qe.question_id = q.id
    left join question_cluster qc on qc.question_id = q.id
    left join dup_closures dc on dc.question_id = q.id
    where q.posttypeid = 1
),
user_question_kpis as (
    select
        qs.user_id,
        count(*) as questions_total,
        avg(qs.vote_events + qs.comment_events) as avg_interactions_per_q,
        sum(case when qs.close_events > 0 then 1 else 0 end) as questions_closed_cnt,
        avg(case when qs.dup_link_count > 0 then 1.0 else 0.0 end) as dup_ratio,
        percentile_cont(0.5) within group (order by qs.net_votes) as median_net_votes
    from question_scores qs
    group by qs.user_id
),
leaderboard as (
    select
        fu.user_id,
        fu.displayname,
        fu.reputation,
        fu.norm_location,
        fu.gold_badges,
        fu.silver_badges,
        fu.bronze_badges,
        fu.last_badge_date,
        fu.question_count,
        fu.answer_count,
        fu.top_tag,
        fu.top_tag_freq,
        fu.distinct_tags_used,
        fu.users_in_location,
        fu.avg_quality_in_location,
        fu.p90_quality_in_location,
        ur.quality_rank,
        uqs.quality_score,
        uqk.questions_total,
        uqk.avg_interactions_per_q,
        uqk.questions_closed_cnt,
        uqk.dup_ratio,
        uqk.median_net_votes
    from final_users fu
    join user_ranked ur on ur.user_id = fu.user_id
    join user_quality_score uqs on uqs.user_id = fu.user_id
    left join user_question_kpis uqk on uqk.user_id = fu.user_id
),
filtered as (
    select
        lb.*,
        row_number() over (
            partition by coalesce(nullif(fu.norm_location,'Unknown'),'Unknown')
            order by lb.quality_score desc, lb.reputation desc
        ) as rn_loc
    from leaderboard lb
    left join final_users fu on fu.user_id = lb.user_id
    where
        lb.quality_score > 0
        and coalesce(lb.answer_count,0) + coalesce(lb.question_count,0) >= 5
        and coalesce(lb.dup_ratio,0) <= 0.5
        and (lb.top_tag is null or lb.top_tag not ilike any (array['%test%','%spam%','meta%']))
)
select
    f.user_id,
    f.displayname,
    f.reputation,
    f.norm_location,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.quality_score,
    f.quality_rank,
    f.question_count,
    f.answer_count,
    f.top_tag,
    f.top_tag_freq,
    f.distinct_tags_used,
    f.questions_total,
    round(coalesce(f.avg_interactions_per_q,0)::numeric, 2) as avg_interactions_per_q,
    f.questions_closed_cnt,
    round(coalesce(f.dup_ratio,0)::numeric, 3) as dup_ratio,
    f.median_net_votes,
    f.users_in_location,
    round(coalesce(f.avg_quality_in_location,0)::numeric, 2) as avg_quality_in_location,
    round(coalesce(f.p90_quality_in_location,0)::numeric, 2) as p90_quality_in_location
from filtered f
where f.rn_loc <= 10
order by f.quality_rank, f.quality_score desc, f.reputation desc, f.user_id
limit 200;