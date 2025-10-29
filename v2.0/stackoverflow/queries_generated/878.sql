-- {"query": "878.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3872} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(u.websiteurl, 'http://example.invalid/' || regexp_replace(coalesce(u.displayname, 'anon'), '\s+', '-', 'g')) as homepage,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '12 months' from posts p)
),
power_users as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate,
           ru.location,
           ru.homepage,
           case when ru.location is null or length(trim(ru.location)) = 0 then 'UNK' else upper(split_part(ru.location, ',', 1)) end as region_key
    from recent_users ru
    where ru.rn <= 5000
),
user_posts as (
    select p.owneruserid as user_id,
           p.id as post_id,
           p.posttypeid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.commentcount,
           p.favoritecount,
           p.closeddate,
           p.acceptedanswerid
    from posts p
    where p.owneruserid is not null
),
post_stats as (
    select up.user_id,
           count(*) filter (where up.posttypeid = 1) as q_count,
           count(*) filter (where up.posttypeid = 2) as a_count,
           sum(up.score) as total_post_score,
           avg(nullif(up.score,0)) as avg_nonzero_score,
           max(up.viewcount) as max_views,
           count(*) filter (where up.closeddate is not null) as closed_count,
           count(*) filter (where up.posttypeid = 1 and up.acceptedanswerid is not null) as accepted_q_count
    from user_posts up
    group by up.user_id
),
votes_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounties_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounties_awarded,
           count(*) filter (where v.votetypeid in (10,12)) as destructive_votes
    from votes v
    group by v.postid
),
user_vote_stats as (
    select up.user_id,
           sum(coalesce(va.upvotes,0)) as received_upvotes,
           sum(coalesce(va.downvotes,0)) as received_downvotes,
           sum(coalesce(va.bounties_started,0)) as bounty_started_sum,
           sum(coalesce(va.bounties_awarded,0)) as bounty_awarded_sum,
           sum(coalesce(va.destructive_votes,0)) as destructive_votes
    from user_posts up
    left join votes_agg va on va.postid = up.post_id
    group by up.user_id
),
comment_engagement as (
    select c.userid as user_id,
           count(*) as comments_made,
           sum(c.score) as comment_score_sum,
           avg(c.score) as comment_score_avg,
           max(c.score) as max_comment_score
    from comments c
    where c.userid is not null
    group by c.userid
),
badges_pivot as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           count(*) filter (where b.tagbased = 1) as tag_badges,
           count(*) filter (where b.tagbased = 0) as named_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
hot_q as (
    select ph.postid,
           min(ph.creationdate) as first_hot_date,
           count(*) as hot_events
    from posthistory ph
    where ph.posthistorytypeid in (52, 53)
    group by ph.postid
),
dup_links as (
    select pl.postid,
           count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
           count(*) filter (where pl.linktypeid = 1) as linked_marks
    from postlinks pl
    group by pl.postid
),
tag_explode as (
    select p.id as post_id,
           lower(trim(both ' ' from t)) as tag
    from posts p
    cross join lateral unnest(string_to_array(coalesce(substring(p.tags, 2, length(p.tags) - 2), ''), '><')) as t
    where p.posttypeid = 1
),
user_top_tags as (
    select up.user_id,
           tt.tag,
           count(*) as tag_q_count,
           row_number() over (partition by up.user_id order by count(*) desc, min(up.post_id)) as tag_rank
    from user_posts up
    join tag_explode te on te.post_id = up.post_id
    join posts p on p.id = up.post_id and p.posttypeid = 1
    join tags tt on tt.tagname = te.tag
    group by up.user_id, tt.tag
),
best_tag as (
    select user_id,
           tag as top_tag,
           tag_q_count
    from user_top_tags
    where tag_rank = 1
),
qa_interactions as (
    select q.owneruserid as asker_id,
           a.owneruserid as answerer_id,
           count(*) as interactions,
           avg(a.score) as avg_answer_score
    from posts a
    join posts q on a.parentid = q.id
    where a.posttypeid = 2 and q.posttypeid = 1 and a.owneruserid is not null and q.owneruserid is not null
    group by q.owneruserid, a.owneruserid
),
user_pair_rank as (
    select qi.answerer_id as user_id,
           qi.asker_id as counterpart_id,
           interactions,
           avg_answer_score,
           row_number() over (partition by qi.answerer_id order by interactions desc, avg_answer_score desc, counterpart_id) as pair_rank
    from qa_interactions qi
),
closest_counterpart as (
    select upr.user_id,
           upr.counterpart_id,
           upr.interactions,
           upr.avg_answer_score
    from user_pair_rank upr
    where upr.pair_rank = 1
),
post_quality as (
    select up.user_id,
           percentile_disc(0.5) within group (order by up.score) as median_post_score,
           percentile_disc(0.9) within group (order by up.score) as p90_post_score
    from user_posts up
    group by up.user_id
),
post_mix as (
    select up.user_id,
           count(*) filter (where up.posttypeid in (3,4,5,7,8)) as wiki_related_count,
           count(*) filter (where up.posttypeid not in (3,4,5,7,8)) as non_wiki_count
    from user_posts up
    group by up.user_id
),
accepted_ratio as (
    select up.user_id,
           count(*) filter (where p.posttypeid = 2 and p.id = q.acceptedanswerid) as answers_accepted,
           count(*) filter (where p.posttypeid = 2) as answers_total
    from user_posts up
    join posts p on p.id = up.post_id
    left join posts q on q.id = p.parentid and p.posttypeid = 2
    group by up.user_id
),
activity_streaks as (
    select up.user_id,
           max(cnt) as max_consec_days
    from (
        select up.user_id,
               date_trunc('day', up.creationdate) as d,
               row_number() over (partition by up.user_id order by date_trunc('day', up.creationdate)) -
               dense_rank() over (partition by up.user_id order by date_trunc('day', up.creationdate)) as grp,
               count(*) over (partition by up.user_id, date_trunc('day', up.creationdate)) as posts_that_day
        from user_posts up
    ) s
    group by s.user_id, s.grp
),
user_flags as (
    select pu.user_id,
           case when ps.q_count + ps.a_count >= 50 and pu.reputation >= 2000 then 1 else 0 end as is_power_contributor,
           case when coalesce(uv.received_downvotes,0) > coalesce(uv.received_upvotes,0) then 1 else 0 end as is_controversial,
           case when coalesce(pm.wiki_related_count,0) > coalesce(pm.non_wiki_count,0) then 1 else 0 end as is_wiki_leaning,
           case when coalesce(hq.hot_events,0) >= 3 then 1 else 0 end as is_often_hot
    from power_users pu
    left join post_stats ps on ps.user_id = pu.user_id
    left join user_vote_stats uv on uv.user_id = pu.user_id
    left join post_mix pm on pm.user_id = pu.user_id
    left join (
        select up.user_id, sum(hq.hot_events) as hot_events
        from user_posts up
        join hot_q hq on hq.postid = up.post_id
        group by up.user_id
    ) hq on hq.user_id = pu.user_id
),
scored_users as (
    select pu.user_id,
           pu.displayname,
           pu.reputation,
           pu.creationdate,
           pu.location,
           pu.homepage,
           pu.region_key,
           coalesce(ps.q_count,0) as q_count,
           coalesce(ps.a_count,0) as a_count,
           coalesce(ps.total_post_score,0) as total_post_score,
           coalesce(ps.avg_nonzero_score,0) as avg_nonzero_score,
           coalesce(ps.max_views,0) as max_views,
           coalesce(ps.closed_count,0) as closed_count,
           coalesce(ps.accepted_q_count,0) as accepted_q_count,
           coalesce(uv.received_upvotes,0) as received_upvotes,
           coalesce(uv.received_downvotes,0) as received_downvotes,
           coalesce(uv.bounty_started_sum,0) as bounty_started_sum,
           coalesce(uv.bounty_awarded_sum,0) as bounty_awarded_sum,
           coalesce(uv.destructive_votes,0) as destructive_votes,
           coalesce(ce.comments_made,0) as comments_made,
           coalesce(ce.comment_score_sum,0) as comment_score_sum,
           coalesce(ce.comment_score_avg,0) as comment_score_avg,
           coalesce(ce.max_comment_score,0) as max_comment_score,
           coalesce(bp.gold_count,0) as gold_badges,
           coalesce(bp.silver_count,0) as silver_badges,
           coalesce(bp.bronze_count,0) as bronze_badges,
           coalesce(bp.tag_badges,0) as tag_badges,
           coalesce(bp.named_badges,0) as named_badges,
           bp.first_badge_date,
           bp.last_badge_date,
           coalesce(btg.top_tag, 'n/a') as top_tag,
           coalesce(btg.tag_q_count,0) as top_tag_qs,
           coalesce(pq.median_post_score,0) as median_post_score,
           coalesce(pq.p90_post_score,0) as p90_post_score,
           coalesce(ac.answers_accepted,0) as answers_accepted,
           coalesce(ac.answers_total,0) as answers_total,
           coalesce(ast.max_consec_days,0) as max_consec_days,
           coalesce(dl.duplicate_marks,0) as duplicate_marks,
           coalesce(dl.linked_marks,0) as linked_marks,
           cc.counterpart_id,
           cc.interactions as top_counterpart_interactions,
           cc.avg_answer_score as top_counterpart_avg_answer_score,
           uf.is_power_contributor,
           uf.is_controversial,
           uf.is_wiki_leaning,
           uf.is_often_hot
    from power_users pu
    left join post_stats ps on ps.user_id = pu.user_id
    left join user_vote_stats uv on uv.user_id = pu.user_id
    left join comment_engagement ce on ce.user_id = pu.user_id
    left join badges_pivot bp on bp.user_id = pu.user_id
    left join best_tag btg on btg.user_id = pu.user_id
    left join post_quality pq on pq.user_id = pu.user_id
    left join accepted_ratio ac on ac.user_id = pu.user_id
    left join activity_streaks ast on ast.user_id = pu.user_id
    left join (
        select up.user_id,
               sum(coalesce(dl.duplicate_marks,0)) as duplicate_marks,
               sum(coalesce(dl.linked_marks,0)) as linked_marks
        from user_posts up
        left join dup_links dl on dl.postid = up.post_id
        group by up.user_id
    ) dl on dl.user_id = pu.user_id
    left join closest_counterpart cc on cc.user_id = pu.user_id
    left join user_flags uf on uf.user_id = pu.user_id
),
ranked as (
    select s.*,
           case when s.answers_total > 0 then s.answers_accepted::numeric / s.answers_total else 0 end as accept_rate,
           case when s.received_upvotes + s.received_downvotes > 0 then s.received_upvotes::numeric / nullif(s.received_upvotes + s.received_downvotes,0) else null end as upvote_ratio,
           greatest(1, s.q_count + s.a_count) as activity_den,
           (
               0.35 * coalesce(s.total_post_score,0)
             + 0.20 * coalesce(s.received_upvotes - s.received_downvotes,0)
             + 0.15 * coalesce(s.bounty_awarded_sum - s.bounty_started_sum,0)
             + 0.10 * (coalesce(s.gold_badges,0)*9 + coalesce(s.silver_badges,0)*3 + coalesce(s.bronze_badges,0))
             + 0.10 * coalesce(s.p90_post_score,0)
             + 0.10 * (case when s.accepted_q_count > 0 then 10 else 0 end)
           ) / sqrt(greatest(1, s.duplicate_marks)) as raw_score
    from scored_users s
),
region_norm as (
    select r.region_key,
           percentile_cont(0.5) within group (order by r.raw_score) as med_score,
           stddev_pop(r.raw_score) as sd_score,
           count(*) as n
    from ranked r
    group by r.region_key
),
finalized as (
    select r.*,
           rn.med_score,
           rn.sd_score,
           case when rn.sd_score is null or rn.sd_score = 0 then null else (r.raw_score - rn.med_score) / rn.sd_score end as zscore,
           row_number() over (
               partition by r.region_key
               order by coalesce((r.raw_score - rn.med_score) / nullif(rn.sd_score,0), r.raw_score) desc,
                        r.reputation desc,
                        r.user_id
           ) as region_rank,
           dense_rank() over (order by r.raw_score desc, r.reputation desc, r.user_id) as global_rank
    from ranked r
    left join region_norm rn on rn.region_key = r.region_key
)
select
    f.user_id,
    f.displayname,
    f.reputation,
    f.location,
    f.homepage,
    f.region_key,
    f.global_rank,
    f.region_rank,
    round(f.raw_score::numeric, 2) as raw_score,
    round(f.zscore::numeric, 2) as zscore,
    f.q_count, f.a_count, f.accept_rate,
    f.received_upvotes, f.received_downvotes, round(coalesce(f.upvote_ratio,0)::numeric, 3) as upvote_ratio,
    f.gold_badges, f.silver_badges, f.bronze_badges, f.tag_badges, f.named_badges,
    f.top_tag, f.top_tag_qs,
    f.max_views, f.median_post_score, f.p90_post_score,
    f.closed_count, f.accepted_q_count,
    f.comments_made, f.comment_score_sum, f.max_comment_score,
    f.duplicate_marks, f.linked_marks,
    f.max_consec_days,
    f.is_power_contributor, f.is_controversial, f.is_wiki_leaning, f.is_often_hot,
    f.counterpart_id, f.top_counterpart_interactions, f.top_counterpart_avg_answer_score,
    f.first_badge_date, f.last_badge_date,
    f.creationdate as user_creationdate
from finalized f
where
    (f.is_power_contributor = 1 or f.raw_score > (select percentile_cont(0.9) within group (order by raw_score) from ranked))
    and (f.q_count + f.a_count) >= 10
    and (f.top_tag is null or f.top_tag not in ('discussion', 'off-topic'))
order by f.global_rank
limit 200;