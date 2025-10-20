with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = false and t2.IsRequired = false
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as TotalQuestionViews,
        sum(case when p.PostTypeId = 2 then p.Score else 0 end) as TotalAnswerScore,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes,
             ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.CreationDate >= (cast('2024-10-01' as date) - interval '1 year')
),
FilteredTopAnswers as (
    select *
    from TopQuestionsWithAnswers
    where AnswerRank = 1
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
AnswerVoteStats as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'AcceptedByOriginator' then 1 else 0 end) as AcceptedCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when av.AcceptedCount > 0 then 1 else 0 end) as AcceptedAnswersCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join AnswerVoteStats av on av.PostId = a.Id
    where q.PostTypeId = 1
    group by q.Id
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalPostScore,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionCreationDate,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViewCount,
    q.Tags,
    qc.ClosedDate,
    qc.ReopenedDate,
    crt.Name as CloseReason,
    fa.AnswerId,
    fa.AnswerCreationDate,
    fa.AnswerScore,
    fa.AnswerOwnerUserId,
    fa.AnswerOwnerDisplayName,
    avs.UpVotes as AnswerUpVotes,
    avs.DownVotes as AnswerDownVotes,
    avs.AcceptedCount as AnswerAcceptedCount,
    qas.TotalAnswers,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    qas.AcceptedAnswersCount,
    string_agg(distinct rth.Path, ' | ') as RelatedTagPaths
from UserReputationWindow u
join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
left join QuestionCloseInfo qc on qc.PostId = q.Id
left join CloseReasonTypes crt on cast(crt.Id as varchar) = qc.CloseReasonId
left join FilteredTopAnswers fa on fa.QuestionId = q.Id
left join AnswerVoteStats avs on avs.PostId = fa.AnswerId
left join QuestionAnswerStats qas on qas.QuestionId = q.Id
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(q.Tags, '')) > 0
where u.Reputation > 1000
  and (qc.ClosedDate is null or qc.ReopenedDate > qc.ClosedDate or qc.ReopenedDate is null)
group by
    u.Id, u.DisplayName, u.Reputation, u.Location, u.Views, u.UpVotes, u.DownVotes, u.QuestionCount, u.AnswerCount, u.TotalPostScore,
    u.GoldBadges, u.SilverBadges, u.BronzeBadges,
    q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags,
    qc.ClosedDate, qc.ReopenedDate, crt.Name,
    fa.AnswerId, fa.AnswerCreationDate, fa.AnswerScore, fa.AnswerOwnerUserId, fa.AnswerOwnerDisplayName,
    avs.UpVotes, avs.DownVotes, avs.AcceptedCount,
    qas.TotalAnswers, qas.MaxAnswerScore, qas.AvgAnswerScore, qas.AcceptedAnswersCount
order by u.Reputation desc, q.Score desc
limit 100;