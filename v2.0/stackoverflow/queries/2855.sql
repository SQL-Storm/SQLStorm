-- {"query": "2855.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1489}
with RecursiveTagCounts as (
    select t.Id as TagId, t.TagName, t.Count,
           coalesce(p.Score, 0) as PostScore,
           rank() over (partition by t.Id order by coalesce(p.Score, 0) desc) as ScoreRank
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    where t.IsModeratorOnly = false and t.IsRequired = false
),
TopPostsPerTag as (
    select TagId, TagName, PostScore
    from RecursiveTagCounts
    where ScoreRank <= 5
),
UserBadgeStats as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
           count(distinct b.Name) as UniqueBadges,
           max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select u.Id as UserId, u.DisplayName,
           count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
           count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
           avg(case when p.PostTypeId in (1,2) then p.Score end) as AvgPostScore,
           max(case when p.PostTypeId in (1,2) then p.Score end) as MaxPostScore,
           sum(case when p.AcceptedAnswerId is not null and p.PostTypeId = 1 then 1 else 0 end) as AcceptedQuestions,
           sum(coalesce(p.ViewCount, 0)) as TotalViews
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserLastActivePosts as (
    select p.OwnerUserId as UserId, max(p.LastActivityDate) as LastActivity
    from Posts p
    group by p.OwnerUserId
),
QualifiedUsers as (
    select ups.UserId, ups.DisplayName, ups.QuestionCount, ups.AnswerCount, ups.AvgPostScore, ups.MaxPostScore, ups.AcceptedQuestions, ups.TotalViews, uls.LastActivity,
           coalesce(ubs.GoldBadges, 0) as GoldBadges, coalesce(ubs.SilverBadges, 0) as SilverBadges, coalesce(ubs.BronzeBadges, 0) as BronzeBadges, coalesce(ubs.UniqueBadges, 0) as UniqueBadges,
           row_number() over (order by ups.AvgPostScore desc NULLS LAST, ups.QuestionCount desc) as UserRank
    from UserPostStats ups
    left join UserBadgeStats ubs on ubs.UserId = ups.UserId
    left join UserLastActivePosts uls on uls.UserId = ups.UserId
    where ups.QuestionCount > 5 and ups.AnswerCount > 10
),
RecentClosedQuestions as (
    select ph.PostId, max(ph.CreationDate) as CloseDate,
           max(case when ph.Comment ~ '101' then 1 else 0 end) as IsDuplicate,
           max(case when ph.Comment ~ '102' then 1 else 0 end) as IsOffTopic,
           count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
TopVotedAnswers as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.Score as AnswerScore, u.DisplayName as AnswerOwner,
           row_number() over (partition by a.ParentId order by a.Score desc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
AnswerVoteSummary as (
    select v.PostId,
           sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
           sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
           count(distinct v.UserId) as UniqueVoters
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
)
select q.Id as QuestionId, q.Title, q.CreationDate, q.Score as QuestionScore, q.ViewCount,
       q.OwnerUserId as QuestionOwnerId, u.DisplayName as QuestionOwnerName,
       coalesce(rcq.CloseVotesCount, 0) as CloseVotes,
       rcq.IsDuplicate, rcq.IsOffTopic,
       ta.AnswerId, ta.AnswerScore, ta.AnswerOwner,
       avs.UpVotes, avs.DownVotes, avs.UniqueVoters,
       qu.DisplayName as TopUser, qu.GoldBadges, qu.SilverBadges, qu.BronzeBadges, qu.UniqueBadges, qu.QuestionCount, qu.AnswerCount, qu.AvgPostScore,
       array_to_string(array_agg(distinct t.TagName order by t.TagName), ', ') as QuestionTags,
       rank() over (partition by q.Id order by ta.AnswerScore desc NULLS LAST) as AnswerScoreRank,
       case when q.AcceptedAnswerId = ta.AnswerId then 1 else 0 end as IsAcceptedAnswer,
       (select count(*) from Comments c where c.PostId = q.Id and c.Score > 0) as PositiveCommentsCount,
       (select count(distinct ph.UserId) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId in (4,5,6) and ph.UserId is not null) as EditorsCount
from Posts q
left join Users u on u.Id = q.OwnerUserId
left join RecentClosedQuestions rcq on rcq.PostId = q.Id
left join TopVotedAnswers ta on ta.QuestionId = q.Id and ta.AnswerRank <= 3
left join AnswerVoteSummary avs on avs.PostId = ta.AnswerId
left join QualifiedUsers qu on qu.UserId = q.OwnerUserId
left join LATERAL (
    select unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as TagName
) t on true
where q.PostTypeId = 1
  and q.Score > 50
  and (q.ClosedDate is null or q.ClosedDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days')
  and (coalesce(qu.GoldBadges, 0) > 0 or coalesce(qu.SilverBadges, 0) > 2 or coalesce(qu.BronzeBadges, 0) > 5)
group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId, u.DisplayName,
         rcq.CloseVotesCount, rcq.IsDuplicate, rcq.IsOffTopic,
         ta.AnswerId, ta.AnswerScore, ta.AnswerOwner,
         avs.UpVotes, avs.DownVotes, avs.UniqueVoters,
         qu.DisplayName, qu.GoldBadges, qu.SilverBadges, qu.BronzeBadges, qu.UniqueBadges, qu.QuestionCount, qu.AnswerCount, qu.AvgPostScore,
         case when q.AcceptedAnswerId = ta.AnswerId then 1 else 0 end,
         q.Id, ta.AnswerScore
order by q.CreationDate desc, ta.AnswerScore desc
limit 100;