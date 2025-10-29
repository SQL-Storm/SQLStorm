-- {"query": "2363.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1686}
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        coalesce(u.Reputation, 0) as OwnerReputation,
        row_number() over (
            partition by p.PostTypeId
            order by p.Score desc, p.ViewCount desc, p.CreationDate desc
        ) as RN
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
      and p.CreationDate >= timestamp '2024-10-01 12:34:56' - interval '1 year'
      and p.Score is not null
),
PostBadgeCounts as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
RecentComments as (
    select
        c.PostId,
        count(*) filter (where c.CreationDate > timestamp '2024-10-01 12:34:56' - interval '30 days') as RecentCommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
PostLinkInfo as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
ClosedPostsWithReason as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
      and crt.Id is not null
),
OwnedPostsWithBadgeAndVotes as (
    select
        rp.Id as PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.OwnerReputation,
        coalesce(pbc.GoldBadges,0) as GoldBadges,
        coalesce(pbc.SilverBadges,0) as SilverBadges,
        coalesce(pbc.BronzeBadges,0) as BronzeBadges,
        rc.RecentCommentCount,
        rc.LastCommentDate,
        pli.LinkedCount,
        pli.DuplicateCount,
        cpwr.CloseReason,
        cpwr.CloseDate,
        (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 2) as UpVotesCount,
        (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 3) as DownVotesCount
    from RankedPosts rp
    left join PostBadgeCounts pbc on rp.OwnerUserId = pbc.UserId
    left join RecentComments rc on rp.Id = rc.PostId
    left join PostLinkInfo pli on rp.Id = pli.PostId
    left join ClosedPostsWithReason cpwr on rp.Id = cpwr.PostId
),
FilteredPosts as (
    select *
    from OwnedPostsWithBadgeAndVotes
    where (GoldBadges + SilverBadges + BronzeBadges) >= 5
      and (UpVotesCount - DownVotesCount) > 10
      and (RecentCommentCount is null or RecentCommentCount > 0)
      and (CloseReason is null or CloseReason not in ('Duplicate', 'Off-topic'))
),
PostWithAnswerPercentile as (
    select
        fp.*,
        case when fp.PostTypeId = 1 then pct.p75 else null end as QAnswerCount75thPercentile
    from (
        select fp.*, coalesce(p.AnswerCount, 0) as AnswerCount
        from FilteredPosts fp
        left join Posts p on fp.PostId = p.Id and p.PostTypeId = 1
    ) fp
    left join (
        select
            1 as PostTypeId,
            percentile_cont(0.75) within group (order by AnswerCount) as p75
        from (
            select coalesce(p2.AnswerCount,0) as AnswerCount
            from FilteredPosts f2
            left join Posts p2 on f2.PostId = p2.Id and p2.PostTypeId = 1
            where f2.PostTypeId = 1
        ) t
    ) pct on fp.PostTypeId = pct.PostTypeId
),
PostWithFormattedTags as (
    select
        *,
        array_to_string(
            array(
                select trim(both ' ' from unnest(string_to_array(
                  regexp_replace(coalesce(Tags, ''), '[<>]', '', 'g')
                  , ' '))
                )
            )
            , ', '
        ) as NormalizedTags
    from PostWithAnswerPercentile
),
FinalRanked as (
    select
        *,
        rank() over (partition by PostTypeId order by Score desc, ViewCount desc, CreationDate desc) as ScoreRank,
        dense_rank() over (partition by PostTypeId order by OwnerReputation desc, GoldBadges desc) as ReputationRank,
        lead(Score) over (partition by PostTypeId order by Score desc, ViewCount desc, CreationDate desc) as NextHigherScore,
        lag(CreationDate) over (partition by PostTypeId order by CreationDate asc) as PreviousPostDate
    from PostWithFormattedTags
    where QAnswerCount75thPercentile is null or AnswerCount >= QAnswerCount75thPercentile
),
UsersWithRecentQualPosts as (
    select
        u.Id,
        u.DisplayName,
        count(distinct fr.PostId) as QualifyingPostCount,
        max(fr.Score) as MaxPostScore,
        sum(fr.ViewCount) as TotalViews,
        bool_or(fr.CloseReason is not null) as HasClosedPosts
    from Users u
    left join FinalRanked fr on u.Id = fr.OwnerUserId
    group by u.Id, u.DisplayName
)
select
    fr.PostId,
    fr.PostTypeId,
    case fr.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostType,
    fr.Title,
    fr.NormalizedTags,
    fr.Score,
    fr.ViewCount,
    fr.OwnerUserId,
    u.DisplayName as OwnerName,
    fr.OwnerReputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.RecentCommentCount,
    fr.LastCommentDate,
    fr.LinkedCount,
    fr.DuplicateCount,
    fr.CloseReason,
    fr.CloseDate,
    fr.UpVotesCount,
    fr.DownVotesCount,
    fr.AnswerCount,
    fr.QAnswerCount75thPercentile,
    fr.ScoreRank,
    fr.ReputationRank,
    fr.NextHigherScore,
    fr.PreviousPostDate,
    uwr.QualifyingPostCount as OwnerQualPostCount,
    uwr.MaxPostScore as OwnerMaxPostScore,
    uwr.TotalViews as OwnerTotalViews,
    uwr.HasClosedPosts as OwnerHasClosedPosts,
    (
        select string_agg(distinct coalesce(Name, ''), ', ')
        from Badges b
        where b.UserId = fr.OwnerUserId
          and b.Date > timestamp '2024-10-01 12:34:56' - interval '1 year'
          and b.Class = 1
    ) as RecentGoldBadges,
    (
        select count(*) from Comments c2
        where c2.PostId = fr.PostId
          and lower(c2.Text) like '%sql%'
          and c2.CreationDate > timestamp '2024-10-01 12:34:56' - interval '90 days'
    ) as RecentSqlCommentsCount
from FinalRanked fr
join Users u on fr.OwnerUserId = u.Id
left join UsersWithRecentQualPosts uwr on u.Id = uwr.Id
where fr.ScoreRank <= 100
order by fr.Score desc, fr.ViewCount desc, fr.CreationDate desc;