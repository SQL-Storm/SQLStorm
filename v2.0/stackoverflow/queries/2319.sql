with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
FilteredPosts as (
    select
        r.UserId,
        r.DisplayName,
        r.PostId,
        r.PostTypeId,
        r.PostCreationDate,
        r.PostScore,
        r.ViewCount,
        r.AnswerCount,
        r.FavoriteCount,
        r.Tags,
        -- normalize tags like '<a><b>' into array ['a','b'] in standard SQL where possible
        string_to_array(substring(coalesce(r.Tags,''), 2, char_length(coalesce(r.Tags,'')) - 2), '><') as TagArray
    from RecursiveUserActivity r
    where r.RecentPostRank <= 5
),
TagActivity as (
    select
        fp.UserId,
        t.Tag,
        count(*) over (partition by fp.UserId) as UserTagPostCount,
        sum(fp.PostScore) over (partition by fp.UserId) as UserTagPostScore,
        max(fp.PostScore) over (partition by fp.UserId, t.Tag) as MaxTagPostScore
    from FilteredPosts fp,
    lateral (
      select unnest(fp.TagArray) as Tag
    ) t
),
BadgeSummary as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when TagBased = true then 1 else 0 end) as TagBasedBadges,
        count(*) as TotalBadges
    from Badges
    group by UserId
),
TopQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.Tags like '%<sql>%'
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        coalesce((select avg(a.Score) from Posts a where a.Id = q.AcceptedAnswerId), 0) as AvgAcceptedAnswerScore,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,
        (select max(uh.LastAccessDate) from Users uh where uh.Id = q.OwnerUserId) as OwnerLastAccess
    from TopQuestions q
),
PostHistoryEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        min(ph.CreationDate) as FirstEditDate,
        max(ph.CreationDate) as LastEditDate,
        count(*) as EditCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId, ph.PostHistoryTypeId
),
UserVoteActivity as (
    select
        v.UserId,
        v.VoteTypeId,
        count(*) as VoteCount
    from Votes v
    where v.UserId is not null
    group by v.UserId, v.VoteTypeId
),
UserLinkActivity as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pl.CreationDate
    from PostLinks pl
),
UnionQuery as (
    select
        ua.UserId,
        ua.DisplayName,
        fs.GoldBadges,
        fs.SilverBadges,
        fs.BronzeBadges,
        fs.TagBasedBadges,
        ta.Tag,
        ta.UserTagPostCount,
        ta.UserTagPostScore,
        ta.MaxTagPostScore
    from RecursiveUserActivity ua
    left join BadgeSummary fs on ua.UserId = fs.UserId
    left join TagActivity ta on ua.UserId = ta.UserId
    where ua.Reputation > 2000

    union

    select
        a.OwnerUserId as UserId,
        cast(null as varchar) as DisplayName,
        0 as GoldBadges,
        0 as SilverBadges,
        0 as BronzeBadges,
        0 as TagBasedBadges,
        cast(null as varchar) as Tag,
        0 as UserTagPostCount,
        0 as UserTagPostScore,
        0 as MaxTagPostScore
    from AcceptedAnswerStats a
),
FinalRanking as (
    select
        uq.UserId,
        uq.DisplayName,
        max(uq.GoldBadges) as MaxGoldBadges,
        max(uq.SilverBadges) as MaxSilverBadges,
        max(uq.BronzeBadges) as MaxBronzeBadges,
        max(uq.TagBasedBadges) as MaxTagBasedBadges,
        count(distinct uq.Tag) as DistinctTags,
        sum(coalesce(uq.UserTagPostCount,0)) as TotalTagPosts,
        avg(coalesce(uq.UserTagPostScore,0)) as AvgTagPostScore,
        max(coalesce(uq.MaxTagPostScore,0)) as MaxTagScore
    from UnionQuery uq
    group by uq.UserId, uq.DisplayName
)
select
    fr.UserId,
    fr.DisplayName,
    fr.MaxGoldBadges,
    fr.MaxSilverBadges,
    fr.MaxBronzeBadges,
    fr.MaxTagBasedBadges,
    fr.DistinctTags,
    fr.TotalTagPosts,
    fr.AvgTagPostScore,
    fr.MaxTagScore,
    us.UpVotes,
    us.DownVotes,
    us.Views,
    us.Reputation,
    us.Location,
    us.LastAccessDate,
    case
        when us.Views > 100000 then 'Very High Views'
        when us.Views > 10000 then 'High Views'
        when us.Views > 1000 then 'Moderate Views'
        else 'Low Views'
    end as ViewCategory,
    coalesce(ph.EditCount,0) as TotalPostEdits,
    coalesce(us.UpVotes - us.DownVotes,0) as VoteDifference
from FinalRanking fr
inner join Users us on us.Id = fr.UserId
left join (
    select p.OwnerUserId as UserId, sum(phe.EditCount) as EditCount
    from PostHistoryEdits phe
    inner join Posts p on p.Id = phe.PostId
    group by p.OwnerUserId
) ph on ph.UserId = fr.UserId
where fr.MaxGoldBadges is not null
order by fr.MaxGoldBadges desc, fr.TotalTagPosts desc, fr.AvgTagPostScore desc
limit 100;