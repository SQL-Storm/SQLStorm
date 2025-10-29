-- {"query": "2997.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1092} 
with recursive UserBadgeSummary as (
  select 
    u.Id as UserId,
    u.DisplayName,
    coalesce(u.Reputation, 0) as Reputation,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    row_number() over (order by coalesce(u.Reputation,0) desc) as UserRank
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
RecentActivity as (
  select
    p.OwnerUserId,
    p.PostTypeId,
    p.Id as PostId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    ph.PostHistoryTypeId,
    ph.CreationDate as HistoryDate,
    ph.UserId as EditorUserId,
    ph.Comment as CloseReasonId
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate > (now() - interval '60 day')
  where p.CreationDate > (now() - interval '180 day')
),
PostLinkData as (
  select
    pl.PostId,
    pl.RelatedPostId,
    lt.Name as LinkTypeName
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
),
UserQuestionStats as (
  select
    r.OwnerUserId,
    count(distinct r.PostId) filter (where r.PostTypeId = 1) as QuestionCount,
    count(distinct r.PostId) filter (where r.PostTypeId = 2) as AnswerCount,
    avg(r.Score) filter (where r.PostTypeId = 1) as AvgQuestionScore,
    avg(r.Score) filter (where r.PostTypeId = 2) as AvgAnswerScore,
    sum(r.ViewCount) filter (where r.PostTypeId = 1) as TotalQuestionViews,
    sum(case when r.PostTypeId = 1 and r.CloseReasonId is not null then 1 else 0 end) as ClosedQuestionsLast60Days
  from RecentActivity r
  group by r.OwnerUserId
),
UserReputationRanking as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    rank() over (order by u.Reputation desc) as RepRank
  from Users u
),
UserTopTags as (
  select
    p.OwnerUserId,
    t.TagName,
    count(*) as TagPostCount,
    row_number() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
  from Posts p
  cross join lateral unnest(string_to_array(substring(coalesce(p.Tags,''),2,length(coalesce(p.Tags,''))-2), '><')) t(TagName)
  where p.PostTypeId = 1
  group by p.OwnerUserId, t.TagName
),
UserTopTagAggregates as (
  select
    ut.OwnerUserId,
    string_agg(ut.TagName || ' (' || ut.TagPostCount || ')', ', ' order by ut.TagPostCount desc) as TopTagsSummary
  from UserTopTags ut
  where ut.TagRank <= 3
  group by ut.OwnerUserId
),
RecentCommentsStats as (
  select
    c.UserId,
    count(c.Id) as CommentCountLast30Days,
    avg(c.Score) as AvgCommentScore
  from Comments c
  where c.CreationDate > (now() - interval '30 day')
  group by c.UserId
)
select 
  ubs.UserRank,
  ubs.DisplayName,
  urs.RepRank,
  ubs.Reputation,
  coalesce(uqs.QuestionCount,0) as QuestionsAsked,
  coalesce(uqs.AnswerCount,0) as AnswersGiven,
  round(coalesce(uqs.AvgQuestionScore,0)::numeric,2) as AvgQScore,
  round(coalesce(uqs.AvgAnswerScore,0)::numeric,2) as AvgAScore,
  coalesce(uqs.TotalQuestionViews,0) as TotalQViews,
  coalesce(uqs.ClosedQuestionsLast60Days,0) as ClosedRecently,
  coalesce(utta.TopTagsSummary, 'None') as TopTags,
  coalesce(rcs.CommentCountLast30Days, 0) as CommentsLast30Days,
  coalesce(round(rcs.AvgCommentScore::numeric,2), 0) as AvgCommentScore
from UserBadgeSummary ubs
left join UserQuestionStats uqs on uqs.OwnerUserId = ubs.UserId
left join UserReputationRanking urs on urs.Id = ubs.UserId
left join UserTopTagAggregates utta on utta.OwnerUserId = ubs.UserId
left join RecentCommentsStats rcs on rcs.UserId = ubs.UserId
where ubs.UserRank <= 100
order by ubs.UserRank;