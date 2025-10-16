-- {"query": "299.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1934} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
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
UserReputationRank as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
PostScoreStats as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(case when p.Score > 0 then 1 else 0 end) as PositiveScoreCount,
        sum(case when p.Score < 0 then 1 else 0 end) as NegativeScoreCount
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId, p.PostTypeId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        u.DisplayName as AnswererName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.CreationDate >= current_date - interval '1 year'
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePosts,
        count(distinct c.Id) over (partition by u.Id order by c.CreationDate rows between unbounded preceding and current row) as CumulativeComments
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
),
UserVoteSummary as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount,
        sum(v.BountyAmount) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId, vt.Name
),
QuestionsWithDuplicateLinks as (
    select
        q.Id as QuestionId,
        q.Title,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        max(pl.CreationDate) as LastDuplicateLinkDate
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
ComplexUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        ur.ReputationRank,
        psq.PostCount as QuestionCount,
        psa.PostCount as AnswerCount,
        psq.AvgScore as AvgQuestionScore,
        psa.AvgScore as AvgAnswerScore,
        uv.FavoriteVotes,
        uv.UpVotes,
        uv.DownVotes,
        uv.TotalBounty
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    left join UserReputationRank ur on ur.UserId = u.Id
    left join PostScoreStats psq on psq.OwnerUserId = u.Id and psq.PostTypeId = 1
    left join PostScoreStats psa on psa.OwnerUserId = u.Id and psa.PostTypeId = 2
    left join (
        select
            v.UserId,
            sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
            sum(coalesce(v.BountyAmount,0)) as TotalBounty
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        where v.UserId is not null
        group by v.UserId
    ) uv on uv.UserId = u.Id
    where u.Reputation > 1000
)
select
    cqs.UserId,
    cqs.DisplayName,
    cqs.ReputationRank,
    cqs.GoldBadges,
    cqs.SilverBadges,
    cqs.BronzeBadges,
    cqs.QuestionCount,
    cqs.AnswerCount,
    cqs.AvgQuestionScore,
    cqs.AvgAnswerScore,
    cqs.FavoriteVotes,
    cqs.UpVotes,
    cqs.DownVotes,
    cqs.TotalBounty,
    coalesce(qd.DuplicateCount, 0) as DuplicateQuestionsLinked,
    coalesce(qd.LastDuplicateLinkDate, timestamp '1970-01-01') as LastDuplicateLink,
    phc.CloseReasonName,
    phc.CloseCount,
    string_agg(distinct rth.TagName, ', ' order by rth.TagName) as SampleTags,
    ua.CreationDate,
    ua.LastAccessDate,
    ua.CumulativePosts,
    ua.CumulativeComments
from ComplexUserStats cqs
left join Posts p on p.OwnerUserId = cqs.UserId and p.PostTypeId = 1
left join QuestionsWithDuplicateLinks qd on qd.QuestionId = p.Id
left join CloseReasonCounts phc on phc.CloseReasonId = (
    select ph.Comment
    from PostHistory ph
    where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc
    limit 1
)
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(p.Tags,''), '><'))
left join UserActivityWindow ua on ua.UserId = cqs.UserId
group by
    cqs.UserId,
    cqs.DisplayName,
    cqs.ReputationRank,
    cqs.GoldBadges,
    cqs.SilverBadges,
    cqs.BronzeBadges,
    cqs.QuestionCount,
    cqs.AnswerCount,
    cqs.AvgQuestionScore,
    cqs.AvgAnswerScore,
    cqs.FavoriteVotes,
    cqs.UpVotes,
    cqs.DownVotes,
    cqs.TotalBounty,
    qd.DuplicateCount,
    qd.LastDuplicateLinkDate,
    phc.CloseReasonName,
    phc.CloseCount,
    ua.CreationDate,
    ua.LastAccessDate,
    ua.CumulativePosts,
    ua.CumulativeComments
order by cqs.ReputationRank
limit 100;