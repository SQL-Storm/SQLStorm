-- {"query": "914.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2775} 
with
recent_users as (
  select
    u.id,
    u.displayname,
    u.location,
    u.reputation,
    u.creationdate,
    u.views,
    u.upvotes,
    u.downvotes,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_stats as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
question_posts as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.closeddate,
    p.communityowneddate,
    row_number() over (partition by p.owneruserid order by p.creationdate desc, p.id desc) as rn_recent_q
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.parentid,
    row_number() over (partition by p.owneruserid order by p.creationdate desc, p.id desc) as rn_recent_a
  from posts p
  where p.posttypeid = 2
),
post_vote_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  group by v.postid
),
q_with_votes as (
  select
    q.*,
    coalesce(v.upvotes,0) as q_upvotes,
    coalesce(v.downvotes,0) as q_downvotes,
    coalesce(v.favorites,0) as q_favorites,
    coalesce(v.bounties_started,0) as q_bounties_started,
    coalesce(v.bounty_total,0) as q_bounty_total
  from question_posts q
  left join post_vote_agg v on v.postid = q.id
),
a_with_votes as (
  select
    a.*,
    coalesce(v.upvotes,0) as a_upvotes,
    coalesce(v.downvotes,0) as a_downvotes
  from answer_posts a
  left join post_vote_agg v on v.postid = a.id
),
user_activity as (
  select
    u.id as userid,
    count(q.id) as total_questions,
    count(a.id) as total_answers,
    sum(coalesce(q.viewcount,0)) as total_q_views,
    sum(coalesce(q.score,0)) as total_q_score,
    sum(coalesce(a.score,0)) as total_a_score,
    sum(coalesce(q.q_upvotes,0)) as total_q_upvotes,
    sum(coalesce(q.q_downvotes,0)) as total_q_downvotes,
    sum(coalesce(a.a_upvotes,0)) as total_a_upvotes,
    sum(coalesce(a.a_downvotes,0)) as total_a_downvotes,
    sum(coalesce(q.q_bounty_total,0)) as total_bounty_awarded,
    count(*) filter (where q.closeddate is not null) as questions_closed
  from recent_users u
  left join q_with_votes q on q.owneruserid = u.id
  left join a_with_votes a on a.owneruserid = u.id
  group by u.id
),
latest_user_q as (
  select owneruserid as userid, id as question_id, title, tags, creationdate, score, viewcount
  from q_with_votes
  where rn_recent_q = 1
),
latest_user_a as (
  select owneruserid as userid, id as answer_id, parentid as question_id, creationdate, score
  from a_with_votes
  where rn_recent_a = 1
),
tag_extract as (
  select
    q.userid,
    unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tag
  from latest_user_q q
),
tag_rank as (
  select
    t.userid,
    t.tag,
    rank() over (partition by t.userid order by tg.count desc nulls last, t.tag) as tag_pop_rank
  from tag_extract t
  left join tags tg on lower(tg.tagname) = lower(t.tag)
),
top_tag as (
  select userid, tag as top_tag
  from tag_rank
  where tag_pop_rank = 1
),
post_close_reasons as (
  select
    ph.postid,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
    max(case
          when ph.posthistorytypeid = 10 then
            nullif(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'), '')
        end) as last_close_reason_id_text
  from posthistory ph
  group by ph.postid
),
dupe_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links
  from postlinks pl
  group by pl.postid
),
question_quality as (
  select
    q.id as postid,
    q.owneruserid as userid,
    q.score,
    q.viewcount,
    q.answercount,
    q.q_upvotes,
    q.q_downvotes,
    q.q_favorites,
    (coalesce(q.score,0) + coalesce(q.q_upvotes,0) - coalesce(q.q_downvotes,0))::numeric
      / nullif(greatest(1, extract(epoch from (now() - q.creationdate)) / 86400)::numeric, 0) as hotness_per_day,
    case when q.closeddate is not null then 1 else 0 end as is_closed,
    coalesce(d.duplicate_links,0) as duplicate_links,
    nullif(last_close_reason_id_text,'')::int as last_close_reason_id
  from q_with_votes q
  left join dupe_links d on d.postid = q.id
  left join post_close_reasons c on c.postid = q.id
),
user_rankings as (
  select
    ua.userid,
    dense_rank() over (order by coalesce(ua.total_q_score + ua.total_a_score,0) desc) as rank_by_score,
    dense_rank() over (order by coalesce(ua.total_q_views,0) desc) as rank_by_views,
    ntile(10) over (order by coalesce(ua.total_a_upvotes,0) desc) as decile_by_answer_upvotes
  from user_activity ua
),
agg_recent_quality as (
  select
    qq.userid,
    count(*) as q_count,
    avg(qq.hotness_per_day) as avg_hotness_per_day,
    percentile_cont(0.9) within group (order by qq.score) as p90_score,
    sum(case when qq.is_closed = 1 then 1 else 0 end) as closed_q,
    count(*) filter (where qq.last_close_reason_id in (101,1)) as duplicates_marked
  from question_quality qq
  where qq.creationdate >= now() - interval '90 days'
  group by qq.userid
),
comment_activity as (
  select
    u.id as userid,
    count(c.id) as comments_made,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments
  from recent_users u
  left join comments c on c.userid = u.id
  group by u.id
),
power_users as (
  select
    u.id as userid
  from user_activity ua
  join users u on u.id = ua.userid
  where ua.total_questions + ua.total_answers >= (
    select percentile_cont(0.95) within group (order by total_questions + total_answers)
    from user_activity
  )
),
combined as (
  select
    ru.id as userid,
    ru.displayname,
    ru.location,
    ru.reputation,
    ru.websiteurl_norm,
    ua.total_questions,
    ua.total_answers,
    ua.total_q_views,
    ua.total_q_score,
    ua.total_a_score,
    ua.total_q_upvotes,
    ua.total_q_downvotes,
    ua.total_a_upvotes,
    ua.total_a_downvotes,
    ua.total_bounty_awarded,
    ua.questions_closed,
    coalesce(ub.total_badges,0) as total_badges,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    ub.first_badge_date,
    ub.last_badge_date,
    coalesce(ub.tag_badges,0) as tag_badges,
    tq.top_tag,
    luq.question_id as latest_question_id,
    luq.title as latest_question_title,
    luq.tags as latest_question_tags,
    lua.answer_id as latest_answer_id,
    lua.question_id as latest_answered_question_id,
    ur.rank_by_score,
    ur.rank_by_views,
    ur.decile_by_answer_upvotes,
    arq.q_count as recent_q_count_90d,
    arq.avg_hotness_per_day as recent_avg_hotness_per_day,
    arq.p90_score as recent_p90_q_score,
    arq.closed_q as recent_closed_q,
    arq.duplicates_marked as recent_duplicates_marked,
    ca.comments_made,
    ca.positive_comments,
    case when pu.userid is not null then 1 else 0 end as is_power_user
  from recent_users ru
  left join user_activity ua on ua.userid = ru.id
  left join user_badge_stats ub on ub.userid = ru.id
  left join top_tag tq on tq.userid = ru.id
  left join latest_user_q luq on luq.userid = ru.id
  left join latest_user_a lua on lua.userid = ru.id
  left join user_rankings ur on ur.userid = ru.id
  left join agg_recent_quality arq on arq.userid = ru.id
  left join comment_activity ca on ca.userid = ru.id
  left join power_users pu on pu.userid = ru.id
)
select *
from (
  select * from combined
  union all
  select
    u.id as userid,
    u.displayname,
    u.location,
    u.reputation,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
    0,0,0,0,0,0,0,0,0,0,
    null,null,0,
    null,null,null,null,
    null::varchar as top_tag,
    null::int as latest_question_id,
    null::varchar as latest_question_title,
    null::varchar as latest_question_tags,
    null::int as latest_answer_id,
    null::int as latest_answered_question_id,
    null::int as rank_by_score,
    null::int as rank_by_views,
    null::int as decile_by_answer_upvotes,
    null::int as recent_q_count_90d,
    null::numeric as recent_avg_hotness_per_day,
    null::numeric as recent_p90_q_score,
    null::int as recent_closed_q,
    null::int as recent_duplicates_marked,
    0 as comments_made,
    0 as positive_comments,
    0 as is_power_user
  from users u
  where not exists (select 1 from combined c where c.userid = u.id)
) final_view
where (coalesce(final_view.total_questions,0) + coalesce(final_view.total_answers,0) > 0)
   or final_view.reputation >= (select percentile_cont(0.99) within group (order by reputation) from users)
order by is_power_user desc, rank_by_score nulls last, total_a_upvotes desc nulls last, reputation desc
limit 500;