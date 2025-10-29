-- {"query": "2193.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1527} 
with recursive UserBadgeCounts as (
    select 
      u.Id as UserId,
      u.DisplayName,
      b.Class,
      count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class
),
UserBadgeSummary as (
    select 
      UserId,
      DisplayName,
      coalesce(sum(case when Class = 1 then BadgeCount else 0 end),0) as GoldBadges,
      coalesce(sum(case when Class = 2 then BadgeCount else 0 end),0) as SilverBadges,
      coalesce(sum(case when Class = 3 then BadgeCount else 0 end),0) as BronzeBadges
    from UserBadgeCounts
    group by UserId, DisplayName
),
PostWithAggregate as (
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
      p.AnswerCount,
      p.FavoriteCount,
      row_number() over (partition by p.PostTypeId order by p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
),
AcceptedAnswers as (
    select 
      q.Id as QuestionId,
      a.Id as AcceptedAnswerId,
      a.OwnerUserId as AcceptedAnswerOwner,
      a.Score as AcceptedAnswerScore
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
UserActivity as (
    select 
      u.Id,
      u.DisplayName,
      count(distinct p.Id) as TotalPosts,
      count(distinct case when p.PostTypeId=1 then p.Id end) as Questions,
      count(distinct case when p.PostTypeId=2 then p.Id end) as Answers,
      coalesce(sum(v.Score),0) as TotalVoteScore,
      min(p.CreationDate) as FirstPostDate,
      max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Votes v on p.Id = v.PostId
    group by u.Id, u.DisplayName
),
LinkedPosts as (
    select 
      pl.PostId,
      pl.RelatedPostId,
      lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
),
PostHistoryEdits as (
    select 
      ph.PostId,
      ph.PostHistoryTypeId,
      pht.Name as HistoryTypeName,
      ph.CreationDate,
      ph.UserId,
      u.DisplayName as EditorName,
      ph.Comment
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId in (4,5,6,10,11) -- edit title, edit body, edit tags, post closed, post reopened
),
TaggedQuestions as (
    select
      p.Id,
      p.Title,
      p.Tags,
      array(
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'))
      ) as TagArray
    from Posts p
    where p.PostTypeId=1 and p.Tags is not null
),
TagCounts as (
    select 
      unnest(TagArray) as Tag,
      count(*) as QuestionCount
    from TaggedQuestions
    group by Tag
),
RankedAnswers as (
    select
      p.*,
      rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
)
select 
  ua.DisplayName as UserName,
  ua.TotalPosts,
  ua.Questions,
  ua.Answers,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  pa.Id as PostId,
  pa.Title as PostTitle,
  pa.PostTypeId,
  pa.Score as PostScore,
  pa.ViewCount,
  coalesce(aa.AcceptedAnswerScore,0) as AcceptedAnswerScore,
  case 
    when pa.PostTypeId = 1 and pa.AcceptedAnswerId is not null then 'Has Accepted Answer'
    when pa.PostTypeId = 1 then 'No Accepted Answer'
    else 'Answer Post'
  end as AcceptedAnswerStatus,
  ph.EditCount,
  ph.ClosedCount,
  array_to_string(array_agg(distinct lt.LinkTypeName), ', ') as LinkTypes,
  tc.Tag as PopularTag,
  tc.QuestionCount as PopularTagQuestionCount,
  ra.AnswerRank,
  case 
    when ua.LastPostDate is not null and ua.FirstPostDate is not null then 
      extract(epoch from (ua.LastPostDate - ua.FirstPostDate))/86400.0
    else null
  end as ActiveDays,
  concat(
    left(ua.DisplayName,3),
    coalesce(cast(ua.TotalPosts as text), '0'),
    '_',
    right(md5(coalesce(ua.DisplayName,'') || cast(ua.Id as text)),4)
  ) as UserCode
from UserActivity ua
left join UserBadgeSummary ubs on ua.Id = ubs.UserId
left join PostWithAggregate pa on pa.OwnerUserId = ua.Id and pa.rn = 1
left join AcceptedAnswers aa on aa.QuestionId = pa.Id
left join (
    select 
      ph.PostId,
      count(case when PostHistoryTypeId in (4,5,6) then 1 end) as EditCount,
      count(case when PostHistoryTypeId = 10 then 1 end) as ClosedCount
    from PostHistory ph
    group by ph.PostId
) ph on ph.PostId = pa.Id
left join LinkedPosts lp on lp.PostId = pa.Id
left join LinkTypes lt on lp.LinkTypeId = lt.Id
left join TagCounts tc on tc.Tag = (select unnest(string_to_array(substring(pa.Tags from 2 for length(pa.Tags)-2), '><')) limit 1)
left join RankedAnswers ra on ra.Id = pa.AcceptedAnswerId
where ua.TotalPosts > 10
group by 
  ua.DisplayName,
  ua.TotalPosts,
  ua.Questions,
  ua.Answers,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  pa.Id,
  pa.Title,
  pa.PostTypeId,
  pa.Score,
  pa.ViewCount,
  aa.AcceptedAnswerScore,
  pa.AcceptedAnswerId,
  ph.EditCount,
  ph.ClosedCount,
  tc.Tag,
  tc.QuestionCount,
  ra.AnswerRank,
  ua.LastPostDate,
  ua.FirstPostDate,
  ua.Id
order by ua.TotalPosts desc, pa.Score desc
limit 100;