-- {"query": "346.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3213} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
           row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(distinct p.id) filter (where p.posttypeid = 1) as questions,
        count(distinct p.id) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score,0)) as post_score,
        sum(coalesce(p.viewcount,0)) as post_views,
        sum(coalesce(p.commentcount,0)) as post_commentcount,
        sum(coalesce(p.favoritecount,0)) as post_favcount,
        count(distinct c.id) as comments_made,
        sum(coalesce(c.score,0)) as comment_score,
        count(distinct v.id) filter (where v.votetypeid = 2) as upvotes_cast,
        count(distinct v.id) filter (where v.votetypeid = 3) as downvotes_cast,
        count(distinct b.id) as badges_earned,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join comments c on c.userid = u.user_id
    left join votes v on v.userid = u.user_id
    left join badges b on b.userid = u.user_id
    group by u.user_id
),
question_details as (
    select
        q.owneruserid as user_id,
        count(*) as total_questions,
        avg(q.score) as avg_q_score,
        percentile_cont(0.5) within group (order by coalesce(q.viewcount,0)) as median_q_views,
        sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_count,
        sum(coalesce(q.answercount,0)) as total_answercount,
        sum(case when q.closeddate is not null then 1 else 0 end) as closed_count
    from posts q
    where q.posttypeid = 1
    group by q.owneruserid
),
answer_details as (
    select
        a.owneruserid as user_id,
        count(*) as total_answers,
        avg(a.score) as avg_a_score,
        sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
        sum(case when a.score < 0 then 1 else 0 end) as negative_answers
    from posts a
    where a.posttypeid = 2
    group by a.owneruserid
),
tag_extraction as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from posts q
    where q.posttypeid = 1
      and q.tags is not null
      and length(q.tags) > 2
),
user_top_tags as (
    select
        t.user_id,
        t.tag,
        count(*) as tag_count,
        dense_rank() over (partition by t.user_id order by count(*) desc, tag) as tag_rank
    from tag_extraction t
    group by t.user_id, t.tag
),
duplicates_and_links as (
    select
        u.user_id,
        count(*) filter (where pl.linktypeid = 3) as dup_links_out,
        count(*) filter (where pl.linktypeid = 1) as linked_out,
        count(*) filter (where pl.linktypeid = 3 and pl.relatedpostid in (select id from posts where owneruserid = u.user_id)) as self_dups
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join postlinks pl on pl.postid = p.id
    group by u.user_id
),
close_events as (
    select
        ph.postid,
        ph.userid as closer_user_id,
        try_cast(ph.comment as int) as close_reason_id,
        min(ph.creationdate) as first_close_date
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid, ph.userid, try_cast(ph.comment as int)
),
close_reason_names as (
    select
        ce.postid,
        ce.closer_user_id,
        coalesce(crt.name, 'Unknown') as close_reason_name,
        ce.first_close_date
    from close_events ce
    left join closereasontypes crt on crt.id = ce.close_reason_id
),
user_closing_activity as (
    select
        u.user_id,
        count(*) as close_votes_made,
        count(*) filter (where crn.close_reason_name ilike '%duplicate%') as close_dup_votes,
        min(crn.first_close_date) as first_close_action
    from recent_users u
    left join close_reason_names crn on crn.closer_user_id = u.user_id
    group by u.user_id
),
hot_bumps as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps,
        count(*) filter (where ph.posthistorytypeid = 52) as selected_hot,
        count(*) filter (where ph.posthistorytypeid = 53) as removed_hot
    from posts p
    left join posthistory ph on ph.postid = p.id
    group by p.owneruserid
),
vote_agg as (
    select
        p.owneruserid as user_id,
        count(*) filter (where vt.votetypeid = 2) as upvotes_received,
        count(*) filter (where vt.votetypeid = 3) as downvotes_received,
        count(*) filter (where vt.votetypeid = 1) as accepts_received,
        sum(coalesce(vt.bountyamount,0)) filter (where vt.votetypeid in (8,9)) as bounty_flow
    from posts p
    left join votes vt on vt.postid = p.id
    group by p.owneruserid
),
user_windows as (
    select
        ru.*,
        lag(ru.reputation) over (order by ru.creationdate) as prev_rep_by_join,
        lead(ru.reputation) over (order by ru.creationdate) as next_rep_by_join,
        avg(ru.reputation) over (order by ru.creationdate rows between 10 preceding and current row) as mov_avg_rep_11
    from recent_users ru
),
synth_scores as (
    select
        ua.user_id,
        coalesce(ua.total_posts,0)
          + coalesce(ua.post_score,0) * 2
          + coalesce(va.upvotes_received,0) * 3
          - coalesce(va.downvotes_received,0) * 2
          + coalesce(va.accepts_received,0) * 5
          + coalesce(udl.dup_links_out,0) * (-1)
          + coalesce(hb.selected_hot,0) * 4
          - coalesce(hb.removed_hot,0) * 2
          + coalesce(qa.accepted_count,0) * 2
          + coalesce(ad.positive_answers,0)
          - coalesce(ad.negative_answers,0) * 2
          + coalesce(ua.badges_earned,0) as activity_score
    from user_activity ua
    left join vote_agg va on va.user_id = ua.user_id
    left join duplicates_and_links udl on udl.user_id = ua.user_id
    left join hot_bumps hb on hb.user_id = ua.user_id
    left join question_details qa on qa.user_id = ua.user_id
    left join answer_details ad on ad.user_id = ua.user_id
),
ranked_users as (
    select
        uw.user_id,
        uw.displayname,
        uw.reputation,
        uw.creationdate,
        ua.total_posts,
        ua.questions,
        ua.answers,
        ua.post_score,
        ua.post_views,
        ua.post_commentcount,
        ua.post_favcount,
        ua.comments_made,
        ua.comment_score,
        ua.badges_earned,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        coalesce(qa.avg_q_score,0) as avg_q_score,
        coalesce(qa.median_q_views,0) as median_q_views,
        coalesce(qa.accepted_count,0) as accepted_count,
        coalesce(qa.total_answercount,0) as total_answercount,
        coalesce(qa.closed_count,0) as closed_count,
        coalesce(ad.avg_a_score,0) as avg_a_score,
        coalesce(ad.positive_answers,0) as positive_answers,
        coalesce(ad.negative_answers,0) as negative_answers,
        coalesce(va.upvotes_received,0) as upvotes_received,
        coalesce(va.downvotes_received,0) as downvotes_received,
        coalesce(va.accepts_received,0) as accepts_received,
        coalesce(va.bounty_flow,0) as bounty_flow,
        coalesce(udl.dup_links_out,0) as dup_links_out,
        coalesce(udl.linked_out,0) as linked_out,
        coalesce(udl.self_dups,0) as self_dups,
        coalesce(uca.close_votes_made,0) as close_votes_made,
        coalesce(uca.close_dup_votes,0) as close_dup_votes,
        uca.first_close_action,
        coalesce(hb.community_bumps,0) as community_bumps,
        coalesce(hb.selected_hot,0) as selected_hot,
        coalesce(hb.removed_hot,0) as removed_hot,
        ss.activity_score,
        row_number() over (
            order by
                ss.activity_score desc,
                ua.total_posts desc,
                uw.reputation desc,
                uw.user_id asc
        ) as overall_rank
    from user_windows uw
    left join user_activity ua on ua.user_id = uw.user_id
    left join question_details qa on qa.user_id = uw.user_id
    left join answer_details ad on ad.user_id = uw.user_id
    left join vote_agg va on va.user_id = uw.user_id
    left join duplicates_and_links udl on udl.user_id = uw.user_id
    left join user_closing_activity uca on uca.user_id = uw.user_id
    left join hot_bumps hb on hb.user_id = uw.user_id
    left join synth_scores ss on ss.user_id = uw.user_id
),
top_tag_concat as (
    select
        utt.user_id,
        string_agg(utt.tag || ':' || utt.tag_count::text, ', ' order by utt.tag_rank, utt.tag) as top_tags_kv
    from user_top_tags utt
    where utt.tag_rank <= 5
    group by utt.user_id
),
null_safety as (
    select
        ru.*,
        coalesce(ttc.top_tags_kv, 'none') as top_tags_kv,
        case
            when ru.websiteurl ilike '%http%' then ru.websiteurl
            when ru.websiteurl = 'N/A' then null
            else 'http://' || ru.websiteurl
        end as normalized_website
    from ranked_users ru
    left join top_tag_concat ttc on ttc.user_id = ru.user_id
),
thresholds as (
    select
        avg(activity_score) as avg_score,
        stddev_pop(activity_score) as sd_score
    from ranked_users
),
flagged as (
    select
        ns.*,
        t.avg_score,
        t.sd_score,
        case
            when ns.activity_score > t.avg_score + 2 * coalesce(t.sd_score,0) then 'outlier_high'
            when ns.activity_score < t.avg_score - 2 * coalesce(t.sd_score,0) then 'outlier_low'
            else 'normal'
        end as activity_flag
    from null_safety ns
    cross join thresholds t
),
finalized as (
    select
        f.*,
        count(*) over () as total_rows,
        rank() over (order by f.activity_score desc) as score_rank,
        dense_rank() over (order by f.reputation desc) as rep_dense_rank,
        percent_rank() over (order by f.activity_score) as pr_activity,
        ntile(10) over (order by f.activity_score desc) as decile_activity
    from flagged f
)
select
    fin.overall_rank,
    fin.user_id,
    coalesce(fin.displayname, '[user ' || fin.user_id::text || ']') as displayname,
    fin.reputation,
    fin.creationdate,
    fin.total_posts,
    fin.questions,
    fin.answers,
    fin.post_score,
    fin.post_views,
    fin.post_commentcount,
    fin.post_favcount,
    fin.comments_made,
    fin.comment_score,
    fin.badges_earned,
    fin.gold_badges,
    fin.silver_badges,
    fin.bronze_badges,
    fin.avg_q_score,
    fin.median_q_views,
    fin.accepted_count,
    fin.total_answercount,
    fin.closed_count,
    fin.avg_a_score,
    fin.positive_answers,
    fin.negative_answers,
    fin.upvotes_received,
    fin.downvotes_received,
    fin.accepts_received,
    fin.bounty_flow,
    fin.dup_links_out,
    fin.linked_out,
    fin.self_dups,
    fin.close_votes_made,
    fin.close_dup_votes,
    fin.first_close_action,
    fin.community_bumps,
    fin.selected_hot,
    fin.removed_hot,
    fin.activity_score,
    fin.score_rank,
    fin.rep_dense_rank,
    fin.pr_activity,
    fin.decile_activity,
    fin.top_tags_kv,
    coalesce(fin.normalized_website, 'unknown') as normalized_website,
    fin.activity_flag,
    fin.total_rows
from finalized fin
where (
        fin.activity_flag <> 'normal'
        or fin.overall_rank <= 100
        or (fin.accepted_count > 0 and fin.answers > fin.questions)
      )
  and coalesce(fin.displayname, '') not ilike '%bot%'
order by fin.overall_rank, fin.user_id
limit 500;