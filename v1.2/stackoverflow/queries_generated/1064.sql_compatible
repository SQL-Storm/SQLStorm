with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over(partition by p.OwnerUserId order by p.CreationDate desc) as rn_latest,
        count(*) over(partition by p.OwnerUserId) as cnt_posts,
        avg(p.Score) over(partition by p.OwnerUserId) as avg_score_user,
        case when p.Tags is not null then array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1)
             else 0 end as tag_count
    from Posts p
    where p.PostTypeId in (1, 2)
), UserBadges as (
    select
        b.UserId,
        b.Class,
        count(*) as badge_count
    from Badges b
    where b.Date > cast('2024-10-01' as date) - interval '1 year'
    group by b.UserId, b.Class
), UserReputationSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ub_gold.badge_count, 0) as gold_badges,
        coalesce(ub_silver.badge_count, 0) as silver_badges,
        coalesce(ub_bronze.badge_count, 0) as bronze_badges,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId
    from Users u
    left join UserBadges ub_gold on ub_gold.UserId = u.Id and ub_gold.Class = 1
    left join UserBadges ub_silver on ub_silver.UserId = u.Id and ub_silver.Class = 2
    left join UserBadges ub_bronze on ub_bronze.UserId = u.Id and ub_bronze.Class = 3
), LatestUserPosts as (
    select
        rp.*
    from RankedPosts rp
    where rp.rn_latest = 1
), UserPostStats as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as question_count,
        count(case when p.PostTypeId = 2 then 1 end) as answer_count,
        sum(p.Score) as total_score,
        avg(p.Score) as avg_score,
        sum(p.ViewCount) as total_views,
        avg(rp.tag_count) as avg_tag_count
    from Posts p
    left join RankedPosts rp on p.Id = rp.Id
    group by p.OwnerUserId
), ComplexQuestions as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.CreationDate,
        (
            select count(distinct ph.PostId)
            from PostHistory ph
            where ph.PostId = q.Id
              and ph.PostHistoryTypeId in (4,5,6)
        ) as edit_count,
        (
            select count(distinct v.Id)
            from Votes v
            where v.PostId = q.Id
              and v.VoteTypeId = 3
        ) as downvotes,
        (
           select string_agg(distinct lt.Name, ', ')
           from PostLinks pl
           join LinkTypes lt on pl.LinkTypeId = lt.Id
           where pl.PostId = q.Id
        ) as linked_types
    from Posts q
    where q.PostTypeId = 1
      and q.Score >= 5
      and q.AnswerCount >= 2
      and q.ViewCount > 100
)
select
    urs.UserId,
    urs.DisplayName,
    urs.Reputation,
    urs.Location,
    urs.gold_badges,
    urs.silver_badges,
    urs.bronze_badges,
    coalesce(ups.question_count,0) as question_count,
    coalesce(ups.answer_count,0) as answer_count,
    coalesce(ups.total_score,0) as total_post_score,
    coalesce(ups.avg_score,0) as avg_post_score,
    coalesce(ups.total_views,0) as total_post_views,
    lup.Title as latest_post_title,
    lup.Score as latest_post_score,
    lup.tag_count as latest_post_tag_count,
    cq.Id as popular_question_id,
    cq.Title as popular_question_title,
    cq.Score as popular_question_score,
    cq.AnswerCount as popular_question_answer_count,
    cq.edit_count as popular_question_edit_count,
    cq.downvotes as popular_question_downvotes,
    cq.linked_types as popular_question_linked_types
from UserReputationSummary urs
left join UserPostStats ups on ups.OwnerUserId = urs.UserId
left join LatestUserPosts lup on lup.OwnerUserId = urs.UserId
left join lateral (
    select *
    from ComplexQuestions cq
    where cq.OwnerUserId = urs.UserId
    order by cq.Score desc, cq.AnswerCount desc
    limit 1
) cq on true
where urs.Reputation > 1000
  and (coalesce(ups.question_count,0) > 0 or coalesce(ups.answer_count,0) > 0)
  and (lup.CreationDate > cast('2024-10-01' as date) - interval '6 months' or lup.CreationDate is null)
order by urs.Reputation desc, coalesce(ups.total_score,0) desc
limit 100;