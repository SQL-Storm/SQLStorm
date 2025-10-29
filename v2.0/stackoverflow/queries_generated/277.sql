-- {"query": "277.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2628} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as country_guess,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
badge_rollup as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           count(*) filter (where p.posttypeid = 2) as answers,
           sum(coalesce(p.viewcount,0)) as total_views,
           sum(coalesce(p.score,0)) as total_score,
           count(*) filter (where p.closeddate is not null) as closed_posts,
           max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
q_tag_breakdown as (
    select p.owneruserid as user_id,
           lower(trim(unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')))) as tag_name,
           count(*) as tag_q_count
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
    group by p.owneruserid, lower(trim(unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'))))
),
top_tags as (
    select q.user_id,
           string_agg(tag_name || ':' || tag_q_count::text, ', ' order by tag_q_count desc, tag_name asc) as tag_stats,
           max(tag_q_count) as max_tag_freq
    from q_tag_breakdown q
    group by q.user_id
),
comment_stats as (
    select c.userid as user_id,
           count(*) as comments_made,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
           sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
           avg(nullif(length(c.text),0)) as avg_comment_len
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_agg as (
    select v.userid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           sum(coalesce(v.bountyamount,0)) as bounty_spent,
           min(v.creationdate) as first_vote_date,
           max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
post_votes_received as (
    select p.owneruserid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_received,
           count(*) filter (where v.votetypeid = 3) as downvotes_received
    from posts p
    left join votes v
      on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
dup_closures as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid = 10 and ph.comment in ('1','101')) as dup_close_events,
           count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
    from posthistory ph
    group by ph.postid
),
link_net as (
    select u.id as user_id,
           sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_out,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links
    from users u
    left join posts p on p.owneruserid = u.id
    left join postlinks pl on pl.postid = p.id
    group by u.id
),
accepted_answer_ratio as (
    select q.owneruserid as user_id,
           count(*) as total_questions,
           sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_count
    from posts q
    where q.posttypeid = 1
      and q.owneruserid is not null
    group by q.owneruserid
),
answer_speed as (
    select a.owneruserid as user_id,
           avg(extract(epoch from (a.creationdate - q.creationdate)) / 3600.0) as avg_answer_latency_hours
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
user_rank as (
    select u.id as user_id,
           dense_rank() over (order by coalesce(pa.total_score,0) desc, coalesce(br.total_badges,0) desc, u.reputation desc) as score_rank,
           percent_rank() over (order by coalesce(pa.total_views,0) desc) as view_percentile
    from users u
    left join post_activity pa on pa.user_id = u.id
    left join badge_rollup br on br.userid = u.id
),
recent_active_posts as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.posttypeid,
           p.creationdate,
           p.lastactivitydate,
           row_number() over (partition by p.owneruserid order by p.lastactivitydate desc nulls last) as rn
    from posts p
    where p.owneruserid is not null
)
select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.country_guess,
    coalesce(pa.questions,0) as questions,
    coalesce(pa.answers,0) as answers,
    coalesce(pa.total_views,0) as total_views,
    coalesce(pa.total_score,0) as total_score,
    coalesce(pa.closed_posts,0) as closed_posts,
    coalesce(br.total_badges,0) as total_badges,
    coalesce(br.gold_badges,0) as gold_badges,
    coalesce(br.silver_badges,0) as silver_badges,
    coalesce(br.bronze_badges,0) as bronze_badges,
    to_char(coalesce(br.first_badge_date, ru.creationdate), 'YYYY-MM-DD') as first_badge_or_join,
    to_char(br.last_badge_date, 'YYYY-MM-DD') as last_badge_date,
    coalesce(pt.upvotes_received,0) - coalesce(pt.downvotes_received,0) as net_votes_received,
    coalesce(va.upvotes_cast,0) - coalesce(va.downvotes_cast,0) as net_votes_cast,
    coalesce(va.bounty_spent,0) as bounty_spent,
    round(coalesce(cs.avg_comment_len,0)::numeric, 2) as avg_comment_len,
    coalesce(cs.comments_made,0) as comments_made,
    coalesce(tt.tag_stats, '(none)') as tag_stats,
    coalesce(tt.max_tag_freq,0) as max_tag_freq,
    coalesce(ln.linked_out,0) as linked_out,
    coalesce(ln.dup_links,0) as duplicate_links,
    coalesce(ar.accepted_count,0) as accepted_answers_on_own_questions,
    coalesce(ar.total_questions,0) as total_questions_asked,
    case when coalesce(ar.total_questions,0) > 0
         then round(100.0 * coalesce(ar.accepted_count,0) / nullif(ar.total_questions,0), 2)
         else null end as question_accept_rate_pct,
    round(coalesce(ans.avg_answer_latency_hours,0)::numeric, 2) as avg_answer_latency_hours,
    ur.score_rank,
    round(ur.view_percentile::numeric, 4) as view_percentile,
    to_char(pa.last_activity, 'YYYY-MM-DD HH24:MI:SS') as last_activity,
    -- complicated predicate-driven classification
    case
        when coalesce(pa.answers,0) >= 50 and coalesce(pa.total_score,0) >= 500 then 'Power Answerer'
        when coalesce(pa.questions,0) >= 50 and coalesce(pa.total_views,0) >= 100000 then 'Prolific Asker'
        when coalesce(br.gold_badges,0) >= 5 then 'Highly Decorated'
        when coalesce(cs.comments_made,0) >= 500 then 'Chatterbox'
        when coalesce(pa.closed_posts,0) >= 10 then 'Controversial'
        else 'Regular'
    end as profile_label,
    -- correlated subqueries for recent behavior
    (
        select count(*)
        from comments c
        where c.userid = ru.user_id
          and c.creationdate >= now() - interval '30 days'
    ) as comments_last_30d,
    (
        select count(*)
        from votes v
        where v.userid = ru.user_id
          and v.votetypeid = 2
          and v.creationdate >= now() - interval '30 days'
    ) as upvotes_cast_last_30d,
    (
        select coalesce(sum(case when ph.posthistorytypeid = 10 and ph.comment in ('1','101') then 1 else 0 end),0)
        from posts p
        left join posthistory ph on ph.postid = p.id
        where p.owneruserid = ru.user_id
    ) as dup_close_events_on_owned_posts,
    -- window function over aggregated results
    rank() over (order by coalesce(pa.total_score,0) desc, coalesce(br.total_badges,0) desc) as global_rank,
    dense_rank() over (partition by case when ru.country_guess = 'Unknown' then null else ru.country_guess end
                       order by coalesce(pa.total_score,0) desc) as country_dense_rank,
    -- recent active post info via outer apply-like left join
    rap.post_id as most_recent_post_id,
    rap.posttypeid as most_recent_post_type,
    to_char(rap.lastactivitydate, 'YYYY-MM-DD HH24:MI:SS') as most_recent_post_activity
from recent_users ru
left join post_activity pa on pa.user_id = ru.user_id
left join badge_rollup br on br.userid = ru.user_id
left join comment_stats cs on cs.user_id = ru.user_id
left join vote_agg va on va.user_id = ru.user_id
left join post_votes_received pt on pt.user_id = ru.user_id
left join top_tags tt on tt.user_id = ru.user_id
left join link_net ln on ln.user_id = ru.user_id
left join accepted_answer_ratio ar on ar.user_id = ru.user_id
left join answer_speed ans on ans.user_id = ru.user_id
left join user_rank ur on ur.user_id = ru.user_id
left join lateral (
    select rap.post_id, rap.posttypeid, rap.lastactivitydate
    from recent_active_posts rap
    where rap.user_id = ru.user_id and rap.rn = 1
) rap on true
where ru.rn <= 1000
qualify (coalesce(pa.total_score,0) + coalesce(br.total_badges,0)) > 0
order by
    (coalesce(pa.total_score,0) + coalesce(br.total_badges,0)) desc,
    ru.reputation desc,
    ru.user_id asc;