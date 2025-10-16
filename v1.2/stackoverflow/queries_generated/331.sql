-- {"query": "331.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1629} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

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
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
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
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    where u.Reputation is not null
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) filter (where a.Id is not null) as AnswerCount,
        max(a.Score) filter (where a.Id is not null) as MaxAnswerScore,
        avg(a.Score) filter (where a.Id is not null) as AvgAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) filter (where a.Id is not null) as AnswersByOwner
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId
),
TopVoters as (
    select
        v.UserId,
        count(*) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
),
LatestUserPosts as (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName
    from Posts p
    join Users u on p.OwnerUserId = u.Id
    where p.CreationDate > current_date - interval '30 days'
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pt1.Name as PostTypeName,
        pt2.Name as RelatedPostTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    join PostTypes pt1 on p1.PostTypeId = pt1.Id
    join PostTypes pt2 on p2.PostTypeId = pt2.Id
    where lt.Name = 'Duplicate'
),
UserBadgesSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
)
select
    qas.QuestionId,
    qas.Title,
    qas.QuestionCreation,
    qas.QuestionScore,
    qas.QuestionViews,
    qas.AnswerCount,
    qas.MaxAnswerScore,
    qas.AvgAnswerScore,
    qas.AnswersByOwner,
    uac.DisplayName as QuestionOwner,
    uac.QuestionsPosted,
    uac.AnswersPosted,
    uac.CommentsMade,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pcr.CloseReason,
    pcr.CloseDate,
    dt.Path as TagHierarchyPath,
    dt.Level as TagHierarchyLevel,
    tv.VoteCount,
    tv.UpVotes,
    tv.DownVotes,
    ur.ReputationRank,
    dup.PostId as DuplicatePostId,
    dup.RelatedPostId as DuplicateRelatedPostId,
    dup.PostTypeName,
    dup.RelatedPostTypeName
from QuestionAnswerStats qas
left join Users uac on uac.Id = (select OwnerUserId from Posts where Id = qas.QuestionId)
left join UserActivityWindow uaw on uaw.UserId = uac.Id
left join UserBadgesSummary ubs on ubs.UserId = uac.Id
left join PostCloseReasons pcr on pcr.PostId = qas.QuestionId
left join Lateral (
    select unnest(string_to_array(substring(qas.Tags, 2, length(qas.Tags) - 2), '><')) as TagName
) tags on true
left join RecursiveTagHierarchy dt on dt.TagName = tags.TagName
left join TopVoters tv on tv.UserId = uac.Id
left join UserReputationRanks ur on ur.Id = uac.Id
left join DuplicateLinks dup on dup.PostId = qas.QuestionId
where qas.AnswerCount > 0
  and (pcr.CloseDate is null or pcr.CloseDate > current_date - interval '180 days')
order by qas.QuestionScore desc, qas.QuestionViews desc
limit 100;