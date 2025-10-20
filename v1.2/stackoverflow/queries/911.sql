with RecursiveUserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.CreationDate) as Rank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), LatestPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId in (1,2) -- Questions and Answers
), PostScoresWindow as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        avg(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 9 preceding and current row) as MovingAvgScoreLast10Posts,
        max(p.Score) over (partition by p.OwnerUserId) as MaxScoreByUser
    from Posts p
    where p.PostTypeId in (1,2)
), TagExploded as (
    select
        p.Id as PostId,
        trim(tg.value) as Tag
    from Posts p,
    lateral (
      -- Convert tags like '<tag1><tag2>' into array by replacing '><' with '>|<' then splitting on '|'
      -- Uses standard SQL functions: replace and regexp_split_to_table if available; fallback to split_part in a generate_series approach isn't used here.
      -- For broad compatibility, use replace + split on '|' via regexp_split_to_table when supported.
      select value from (
        select regexp_split_to_table(replace(substring(p.Tags from 2 for length(p.Tags) - 2), '><', '>|<'), '\\|') as value
      ) s
    ) as tg
    where p.Tags is not null and p.PostTypeId = 1
), TopTagsByUser as (
    select
        t.Tag,
        p.OwnerUserId,
        count(*) as UsageCount,
        rank() over (partition by p.OwnerUserId order by count(*) desc) as TagUsageRank
    from TagExploded t
    join Posts p on p.Id = t.PostId
    group by t.Tag, p.OwnerUserId
    having count(*) > 2
), DuplicateQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
), QuestionCloseCounts as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseDate
    from PostHistory ph
    join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    group by ph.PostId
)
select
    rus.UserId,
    rus.DisplayName,
    rus.Reputation,
    rus.GoldBadges,
    rus.SilverBadges,
    rus.BronzeBadges,
    lp.Id as LatestPostId,
    lp.PostTypeId,
    lp.Title,
    coalesce(lp.Tags, '') as Tags,
    coalesce(psw.MovingAvgScoreLast10Posts, 0) as UserAvgScoreLast10Posts,
    coalesce(psw.MaxScoreByUser, 0) as UserMaxScore,
    coalesce(ttbu.Tag, 'N/A') as TopTag,
    coalesce(ttbu.UsageCount, 0) as TopTagUsageCount,
    dcq.DuplicateQuestionId,
    dcq.OriginalQuestionId,
    qcc.CloseCount,
    qcc.ReopenCount,
    qcc.LastCloseDate,
    case
        when qcc.CloseCount > qcc.ReopenCount then 'Mostly Closed'
        when qcc.ReopenCount > 0 then 'Reopened'
        else 'Open'
    end as PostStatus,
    coalesce(
        (select count(*)
         from Comments c
         where c.PostId = lp.Id
           and ((c.Text ilike '%performance%') or (c.Text ilike '%benchmark%'))
           and c.CreationDate > lp.CreationDate - interval '90 days'), 0) as RecentPerformanceComments,
    concat_ws(' | ',
      rus.DisplayName,
      concat('Rep: ', rus.Reputation),
      concat('Badges: G', rus.GoldBadges, '/S', rus.SilverBadges, '/B', rus.BronzeBadges),
      coalesce(lp.Title, 'No Title'),
      coalesce(ttbu.Tag, 'No Top Tag')) as UserSummary
from RecursiveUserBadgeStats rus
left join LatestPosts lp on lp.OwnerUserId = rus.UserId and lp.rn = 1
left join PostScoresWindow psw on psw.Id = lp.Id
left join TopTagsByUser ttbu on ttbu.OwnerUserId = rus.UserId and ttbu.TagUsageRank = 1
left join DuplicateQuestions dcq on dcq.DuplicateQuestionId = lp.Id
left join QuestionCloseCounts qcc on qcc.PostId = lp.Id
where rus.Reputation > 5000
  and (psw.MovingAvgScoreLast10Posts > 5 or rus.GoldBadges >= 3)
order by rus.Reputation desc, psw.MovingAvgScoreLast10Posts desc
limit 100;