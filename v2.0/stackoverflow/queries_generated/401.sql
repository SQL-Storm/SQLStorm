-- {"query": "401.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3189} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
           count(distinct b.id) filter (where b.class = 1) as gold_badges,
           count(distinct b.id) filter (where b.class = 2) as silver_badges,
           count(distinct b.id) filter (where b.class = 3) as bronze_badges,
           max(b.date) as last_badge_date
    from users u
    left join badges b
      on b.userid = u.id
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
question_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           count(*) filter (where p.posttypeid = 2) as answers,
           sum(coalesce(p.score,0)) as post_score,
           sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
           count(*) filter (where p.closeddate is not null) as closed_posts,
           avg(nullif(p.answercount,0)) filter (where p.posttypeid = 1) as avg_answers_per_question,
           min(p.creationdate) as first_post_date,
           max(p.creationdate) as last_post_date
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answerers as (
    select a.owneruserid as user_id,
           count(*) as accepted_answers
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.posttypeid = 1
    group by a.owneruserid
),
tag_stats as (
    select p.owneruserid as user_id,
           t.tagname,
           count(*) as tag_posts,
           sum(p.score) as tag_score,
           row_number() over (partition by p.owneruserid order by count(*) desc, sum(p.score) desc, min(p.creationdate)) as rn_posts,
           row_number() over (partition by p.owneruserid order by sum(p.score) desc nulls last, count(*) desc) as rn_score
    from posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
    ) x
    join tags t
      on lower(t.tagname) = lower(x.tagname)
    where p.posttypeid = 1
      and p.tags is not null
    group by p.owneruserid, t.tagname
),
top_tags as (
    select user_id,
           max(case when rn_posts = 1 then tagname end) as top_tag_by_posts,
           max(case when rn_score = 1 then tagname end) as top_tag_by_score
    from tag_stats
    where rn_posts = 1 or rn_score = 1
    group by user_id
),
voting_agg as (
    select v.userid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 5) as favorites_cast,
           count(*) filter (where v.votetypeid in (8,9)) as bounties_touch,
           sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from votes v
    where v.userid is not null
    group by v.userid
),
comment_agg as (
    select c.userid as user_id,
           count(*) as comments_made,
           sum(coalesce(c.score,0)) as comment_score,
           max(length(c.text)) as longest_comment_len,
           avg(length(c.text))::numeric(18,2) as avg_comment_len
    from comments c
    where c.userid is not null
    group by c.userid
),
postlink_agg as (
    select p.owneruserid as user_id,
           count(*) filter (where pl.linktypeid = 1 and pl.postid = p.id) as links_from_posts,
           count(*) filter (where pl.linktypeid = 1 and pl.relatedpostid = p.id) as links_to_posts,
           count(*) filter (where pl.linktypeid = 3 and pl.postid = p.id) as marked_duplicate_of,
           count(*) filter (where pl.linktypeid = 3 and pl.relatedpostid = p.id) as has_duplicates_pointing_to
    from posts p
    left join postlinks pl
      on pl.postid = p.id or pl.relatedpostid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
closed_reasons as (
    select ph.postid,
           max(crt.name) filter (where ph.posthistorytypeid = 10) as close_reason_name
    from posthistory ph
    left join closereasontypes crt
      on crt.id::varchar = nullif(trim(ph.comment), '')
    where ph.posthistorytypeid in (10)
    group by ph.postid
),
question_quality as (
    select p.owneruserid as user_id,
           percentile_disc(0.5) within group (order by coalesce(p.score,0)) as median_question_score,
           percentile_disc(0.5) within group (order by coalesce(p.viewcount,0)) as median_question_views,
           count(*) filter (where p.answercount > 0) as answered_questions,
           count(*) filter (where p.acceptedanswerid is not null) as questions_with_accepted,
           count(*) filter (where cr.close_reason_name ilike '%duplicate%') as duplicates_closed,
           count(*) filter (where cr.close_reason_name is not null) as total_closed
    from posts p
    left join closed_reasons cr
      on cr.postid = p.id
    where p.posttypeid = 1
      and p.owneruserid is not null
    group by p.owneruserid
),
user_rank as (
    select ru.user_id,
           rank() over (order by ru.reputation desc, coalesce(qa.post_score,0) desc, coalesce(aa.accepted_answers,0) desc) as rep_rank,
           dense_rank() over (order by coalesce(qa.questions,0) + coalesce(qa.answers,0) desc) as activity_rank,
           row_number() over (order by coalesce(va.bounty_amount_total,0) desc) as bounty_rank
    from recent_users ru
    left join question_activity qa on qa.user_id = ru.user_id
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join voting_agg va on va.user_id = ru.user_id
),
time_buckets as (
    select p.owneruserid as user_id,
           date_trunc('month', p.creationdate) as month,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(coalesce(p.score,0)) as score_sum
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
streaks as (
    select tb.user_id,
           max(streak_len) as max_monthly_activity_streak
    from (
        select user_id,
               month,
               sum(is_active) over (partition by user_id order by month
                    rows between unbounded preceding and current row)
               - sum(gap) over (partition by user_id order by month
                    rows between unbounded preceding and current row) as grp,
               is_active
        from (
            select user_id,
                   month,
                   case when q_count + a_count > 0 then 1 else 0 end as is_active,
                   case when lag(month) over (partition by user_id order by month) = month - interval '1 month' then 0 else 1 end as gap
            from (
                select user_id, month, q_count, a_count
                from time_buckets
            ) z
        ) y
    ) x
    cross join lateral (
        select coalesce(max(cnt),0) as streak_len
        from (
            select user_id, grp, count(*) as cnt
            from (
                select user_id, month, grp
                from x
                where is_active = 1
            ) s
            group by user_id, grp
        ) t
    ) k
    group by user_id
),
synthesis as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ru.last_badge_date,
        coalesce(qa.questions,0) as questions,
        coalesce(qa.answers,0) as answers,
        coalesce(qa.post_score,0) as post_score,
        coalesce(qa.question_views,0) as question_views,
        coalesce(qa.closed_posts,0) as closed_posts,
        coalesce(qa.avg_answers_per_question,0) as avg_answers_per_question,
        qa.first_post_date,
        qa.last_post_date,
        coalesce(aa.accepted_answers,0) as accepted_answers,
        coalesce(va.upvotes_cast,0) as upvotes_cast,
        coalesce(va.downvotes_cast,0) as downvotes_cast,
        coalesce(va.favorites_cast,0) as favorites_cast,
        coalesce(va.bounties_touch,0) as bounties_touch,
        coalesce(va.bounty_amount_total,0) as bounty_amount_total,
        coalesce(ca.comments_made,0) as comments_made,
        coalesce(ca.comment_score,0) as comment_score,
        coalesce(ca.longest_comment_len,0) as longest_comment_len,
        coalesce(ca.avg_comment_len,0) as avg_comment_len,
        coalesce(pl.links_from_posts,0) as links_from_posts,
        coalesce(pl.links_to_posts,0) as links_to_posts,
        coalesce(pl.marked_duplicate_of,0) as marked_duplicate_of,
        coalesce(pl.has_duplicates_pointing_to,0) as has_duplicates_pointing_to,
        qq.median_question_score,
        qq.median_question_views,
        coalesce(qq.answered_questions,0) as answered_questions,
        coalesce(qq.questions_with_accepted,0) as questions_with_accepted,
        coalesce(qq.duplicates_closed,0) as duplicates_closed,
        coalesce(qq.total_closed,0) as total_closed,
        tt.top_tag_by_posts,
        tt.top_tag_by_score,
        ur.rep_rank,
        ur.activity_rank,
        ur.bounty_rank,
        coalesce(st.max_monthly_activity_streak,0) as max_monthly_activity_streak,
        case
            when coalesce(qa.answers,0) = 0 then null
            else round(coalesce(aa.accepted_answers,0)::numeric / nullif(qa.answers,0), 4)
        end as answer_accept_rate,
        case
            when coalesce(qa.questions,0) = 0 then null
            else round(coalesce(qq.questions_with_accepted,0)::numeric / nullif(qa.questions,0), 4)
        end as question_accept_presence,
        case
            when coalesce(va.upvotes_cast,0) + coalesce(va.downvotes_cast,0) = 0 then null
            else round((coalesce(va.upvotes_cast,0)::numeric - coalesce(va.downvotes_cast,0)) / nullif((coalesce(va.upvotes_cast,0) + coalesce(va.downvotes_cast,0)),0), 4)
        end as vote_polarity,
        case
            when ru.websiteurl ilike '%github%' then 'github'
            when ru.websiteurl ilike '%stackexchange%' then 'stackexchange'
            when ru.websiteurl = 'n/a' then null
            else 'other'
        end as website_category
    from recent_users ru
    left join question_activity qa on qa.user_id = ru.user_id
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join voting_agg va on va.user_id = ru.user_id
    left join comment_agg ca on ca.user_id = ru.user_id
    left join postlink_agg pl on pl.user_id = ru.user_id
    left join question_quality qq on qq.user_id = ru.user_id
    left join top_tags tt on tt.user_id = ru.user_id
    left join user_rank ur on ur.user_id = ru.user_id
    left join streaks st on st.user_id = ru.user_id
),
outliers as (
    select s.*,
           avg(post_score) over () as avg_post_score_all,
           stddev_pop(post_score) over () as sd_post_score_all,
           avg(reputation) over () as avg_reputation_all,
           stddev_pop(reputation) over () as sd_reputation_all,
           case
               when sd_post_score_all > 0 and (s.post_score - avg_post_score_all) / sd_post_score_all >= 3 then 1
               else 0
           end as is_post_score_outlier,
           case
               when sd_reputation_all > 0 and (s.reputation - avg_reputation_all) / sd_reputation_all >= 3 then 1
               else 0
           end as is_reputation_outlier
    from synthesis s
)
select *
from outliers
where coalesce(reputation,0) >= 0
  and (
      is_post_score_outlier = 1
      or is_reputation_outlier = 1
      or (
          coalesce(questions,0) + coalesce(answers,0) > 0
          and (
               coalesce(question_views,0) > 10000
               or coalesce(post_score,0) > 100
               or coalesce(accepted_answers,0) >= 10
               or coalesce(duplicates_closed,0) >= 5
               or coalesce(max_monthly_activity_streak,0) >= 6
          )
      )
  )
order by reputation desc nulls last, post_score desc nulls last, accepted_answers desc nulls last
limit 200;