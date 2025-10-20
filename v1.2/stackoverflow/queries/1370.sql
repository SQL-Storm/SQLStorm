with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(
            trim(both '<>' from coalesce(p.Tags, '')), 
            '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
), TaggedPostRanks as (
    select
        rtg.Tag,
        rtg.PostId,
        row_number() over (partition by rtg.Tag order by p.Score desc, p.ViewCount desc) as TagRank
    from RecursiveTagCounts rtg
    join Posts p on p.Id = rtg.PostId
), UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), PostVoteSummary as (
    select 
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavVotes,
        count(*) as TotalVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
), QuestionAnswerLink as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreated,
        lag(a.Score) over (partition by q.Id order by a.Score desc) as PrevAnswerScore,
        lead(a.Score) over (partition by q.Id order by a.Score desc) as NextAnswerScore,
        abs(a.Score - coalesce(lag(a.Score) over (partition by q.Id order by a.Score desc), 0)) as PrevAnswerDiff,
        abs(a.Score - coalesce(lead(a.Score) over (partition by q.Id order by a.Score desc), 0)) as NextAnswerDiff
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
), UserPostsPerformance as (
    select
        u.Id as UserId,
        coalesce(count(distinct q.Id),0) as QuestionCount,
        coalesce(avg(q.Score),0) as AvgQuestionScore,
        coalesce(count(distinct a.Id),0) as AnswerCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        greatest(max(q.CreationDate), max(a.CreationDate)) as LastActivePostDate,
        -- convert LastAccessDate to timestamp in a cross-dialect way: assume it's already timestamp or datetime
        coalesce(u.LastAccessDate, null) as LastAccess,
        (
            (coalesce(avg(q.Score),0)*1.5 * coalesce(count(distinct q.Id),0)) +
            (coalesce(avg(a.Score),0)*2.0 * coalesce(count(distinct a.Id),0))
        ) * 
        (1 + u.Reputation/10000.0) * 
        (1 + (
            (select coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) from Badges b where b.UserId = u.Id)
        )/10.0 + (
            (select coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) from Badges b where b.UserId = u.Id)
        )/50.0)
        as PerformanceIndex
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id, u.Reputation, u.LastAccessDate
), DuplicateLinkedQuestions as (
    select 
        p.Id as QuestionId,
        p.Title,
        pl.RelatedPostId as DuplicateOfId,
        dup.Title as DuplicateTitle
    from Posts p
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    join Posts dup on dup.Id = pl.RelatedPostId
    where p.PostTypeId = 1 and dup.PostTypeId = 1
), TopComplexUsers as (
    select
        up.UserId,
        u.DisplayName,
        up.PerformanceIndex,
        ubr.TotalBadges,
        up.QuestionCount,
        up.AnswerCount,
        case when up.LastActivePostDate is null then 'No Posts' 
             else cast(cast(up.LastActivePostDate as date) as varchar) end as LastActive,
        dense_rank() over (order by up.PerformanceIndex desc) as RankPerformance
    from UserPostsPerformance up
    join Users u on u.Id = up.UserId
    join UserBadgeCounts ubr on ubr.UserId = up.UserId
    where up.PerformanceIndex > 100
)

select 
    tc.Tag as TrendingTag,
    p.Id as QuestionId,
    p.Title,
    p.Score,
    p.ViewCount,
    pv.UpVotes,
    pv.DownVotes,
    pv.FavVotes,
    qal.AnswerId,
    qal.AnswerScore,
    qal.AnswerCreated,
    dup.DuplicateOfId,
    dup.DuplicateTitle,
    topc.DisplayName as TopContributorDisplayName,
    topc.PerformanceIndex,
    topc.RankPerformance,
    topc.TotalBadges
from TaggedPostRanks tc
join Posts p on p.Id = tc.PostId
left join PostVoteSummary pv on pv.PostId = p.Id
left join QuestionAnswerLink qal on qal.QuestionId = p.Id and qal.AnswerScore = (
    select max(Score) from Posts where ParentId = p.Id and PostTypeId=2
)
left join DuplicateLinkedQuestions dup on dup.QuestionId = p.Id
left join TopComplexUsers topc on topc.UserId = p.OwnerUserId
where tc.TagRank <= 5
order by tc.Tag, p.Score desc, p.ViewCount desc
limit 100;