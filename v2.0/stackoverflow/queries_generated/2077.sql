-- {"query": "2077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1777} 
with RecursiveTagCTE as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Depth,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Depth + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagCTE r on t.Id <> all(r.Path)
    where t.Count > r.Count / 2 and r.Depth < 3
),
LatestUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentDate,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Votes v on v.PostId = p2.Id and v.UserId <> u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PostRanking as (
    select
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRecencyRank,
        count(*) over (partition by p.OwnerUserId, p.PostTypeId) as UserPostCount,
        array_length(string_to_array(coalesce(p.Tags,'')::text, '><'), 1) as TagCount
    from Posts p
    where p.PostTypeId in (1, 2)
),
HighImpactPosts as (
    select
        pr.Id as PostId,
        pr.Title,
        pr.Score,
        pr.ViewCount,
        pr.OwnerUserId,
        ru.DisplayName as OwnerName,
        pr.CreationDate,
        pr.TagCount,
        pr.ScoreRank,
        pr.UserPostRecencyRank,
        pr.UserPostCount,
        case
            when pr.Score > 100 and pr.ViewCount > 10000 then 'High'
            when pr.Score between 50 and 100 then 'Medium'
            else 'Low'
        end as ImpactLevel,
        (select count(*) from Comments c where c.PostId = pr.Id and (c.Text ilike '%error%' or c.Text ilike '%fail%')) as ErrorCommentsCount,
        (select count(*) from Votes v where v.PostId = pr.Id and v.VoteTypeId = 3) as DownVotesCount,
        (select max(History.CreationDate) from PostHistory History where History.PostId = pr.Id and History.PostHistoryTypeId in (10,11)) as LastCloseOrReopenDate
    from PostRanking pr
    left join Users ru on ru.Id = pr.OwnerUserId
    where pr.Score > 10
),
FinalAggregate as (
    select
        li.PostId,
        li.Title,
        li.Score,
        li.ViewCount,
        li.OwnerUserId,
        li.OwnerName,
        li.CreationDate,
        li.TagCount,
        li.ScoreRank,
        li.UserPostRecencyRank,
        li.UserPostCount,
        li.ImpactLevel,
        coalesce(li.ErrorCommentsCount,0) as ErrorCommentsCount,
        coalesce(li.DownVotesCount,0) as DownVotesCount,
        li.LastCloseOrReopenDate,
        lu.Reputation,
        lu.GoldBadges,
        lu.SilverBadges,
        lu.BronzeBadges,
        lu.Location,
        coalesce((select max(S.PostHistoryTypeId) from PostHistory S where S.PostId = li.PostId and S.PostHistoryTypeId in (25,33,34)), 0) as SpecialPostHistoryFlag,
        array_agg(distinct rt.TagName order by rt.TagName) filter (where rt.Id is not null) as RelatedTags
    from HighImpactPosts li
    left join LatestUserActivity lu on lu.Id = li.OwnerUserId
    left join RecursiveTagCTE rt on rt.TagName = any(string_to_array(coalesce(li.Tags,'')::text, '><'))
    group by
        li.PostId, li.Title, li.Score, li.ViewCount, li.OwnerUserId, li.OwnerName, li.CreationDate, li.TagCount, li.ScoreRank,
        li.UserPostRecencyRank, li.UserPostCount, li.ImpactLevel, li.ErrorCommentsCount, li.DownVotesCount, li.LastCloseOrReopenDate,
        lu.Reputation, lu.GoldBadges, lu.SilverBadges, lu.BronzeBadges, lu.Location
),
ClosedOrDuplicateLinks as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinkCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPostCount
    from PostLinks pl
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
FinalResult as (
    select
        fa.PostId,
        fa.Title,
        fa.Score,
        fa.ViewCount,
        fa.OwnerUserId,
        fa.OwnerName,
        fa.Reputation,
        fa.Location,
        fa.GoldBadges,
        fa.SilverBadges,
        fa.BronzeBadges,
        fa.CreationDate,
        fa.TagCount,
        fa.ImpactLevel,
        fa.ErrorCommentsCount,
        fa.DownVotesCount,
        fa.LastCloseOrReopenDate,
        fa.SpecialPostHistoryFlag,
        fa.RelatedTags,
        coalesce(cd.DuplicateLinkCount, 0) as DuplicateLinkCount,
        coalesce(cd.LinkedPostCount, 0) as LinkedPostCount,
        case when fa.LastCloseOrReopenDate is null then null else date_part('epoch', now() - fa.LastCloseOrReopenDate)::int end as SecondsSinceLastCloseOrReopen
    from FinalAggregate fa
    left join ClosedOrDuplicateLinks cd on cd.PostId = fa.PostId
    where fa.ImpactLevel in ('High', 'Medium')
)
select
    fr.PostId,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.OwnerUserId,
    fr.OwnerName,
    fr.Reputation,
    fr.Location,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.CreationDate,
    fr.TagCount,
    fr.ImpactLevel,
    fr.ErrorCommentsCount,
    fr.DownVotesCount,
    fr.LastCloseOrReopenDate,
    fr.SpecialPostHistoryFlag,
    fr.DuplicateLinkCount,
    fr.LinkedPostCount,
    fr.SecondsSinceLastCloseOrReopen,
    array_to_string(fr.RelatedTags, ', ') as RelatedTags,
    case when fr.GoldBadges + fr.SilverBadges + fr.BronzeBadges > 10 then 'Veteran' else 'Regular' end as UserBadgeCategory,
    case
        when fr.Reputation > 10000 then 'Expert'
        when fr.Reputation between 5000 and 10000 then 'Intermediate'
        else 'Novice'
    end as UserReputationCategory
from FinalResult fr
order by fr.Score desc, fr.ViewCount desc, fr.CreationDate asc
limit 100;