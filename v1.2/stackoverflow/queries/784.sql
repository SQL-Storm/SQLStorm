with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000 and p.PostTypeId in (1,2)
),
UserBadgeStats as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TopTags as (
    select
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.ViewCount,0) as ViewCount,
        t.IsModeratorOnly,
        t.IsRequired
    from Tags t
    left join (
        select
            tag as TagName,
            sum(AnswerCount) as AnswerCount,
            sum(ViewCount) as ViewCount
        from (
            select
                trim(both '<>' from substring(p.Tags from 2 for (length(p.Tags) - 2))) as inner_tags,
                p.AnswerCount,
                p.ViewCount
            from Posts p
            where p.PostTypeId = 1
        ) x,
        lateral (
            -- split inner_tags on '><' and unnest in a dialect-agnostic way using regexp_split_to_table when available,
            -- fallback to splitting using a simple replace+split approach for common engines
            select value as tag from (
                select regexp_split_to_table(x.inner_tags, '><') as value
            ) s
        ) s2
        group by tag
    ) p on p.TagName = t.TagName
    where t.Count > 1000
),
PostLinkAgg as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
UserVoteSummary as (
    select
        u.Id as UserId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotesGiven,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotesGiven,
        count(distinct v.PostId) as DistinctPostsVoted,
        coalesce(sum(coalesce(v.BountyAmount,0)),0) as TotalBountyGiven
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id
),
QuestionAnswerRatio as (
    select
        OwnerUserId,
        count(case when PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when PostTypeId = 2 then 1 end) as AnswerCount,
        case when count(case when PostTypeId = 1 then 1 end) = 0 then null
             else (cast(count(case when PostTypeId = 2 then 1 end) as numeric) / nullif(cast(count(case when PostTypeId = 1 then 1 end) as numeric),0))
        end as AnswerQuestionRatio
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
),
RecentPostActivity as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.Comment,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as HistoryRankDesc
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId = 1 and p.CreationDate > (cast('2024-10-01' as date) - interval '180 days')
)
select
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(ubs.DistinctBadges,0) as DistinctBadges,
    coalesce(uvs.UpVotesGiven,0) as UpVotesGiven,
    coalesce(uvs.DownVotesGiven,0) as DownVotesGiven,
    coalesce(uvs.DistinctPostsVoted,0) as DistinctPostsVoted,
    coalesce(uvs.TotalBountyGiven,0) as TotalBountyGiven,
    qar.QuestionCount,
    qar.AnswerCount,
    qar.AnswerQuestionRatio,
    rua.PostId,
    rua.PostTypeId,
    rua.PostScore,
    rua.ViewCount,
    rua.Title,
    -- use standard length() instead of dialect-specific char_length
    substring(rua.Tags from 2 for (length(rua.Tags) - 2)) as CleanTags,
    pla.DuplicateCount,
    pla.LinkedCount,
    tt.TagName,
    tt.Count as TagGlobalCount,
    tt.IsModeratorOnly,
    tt.IsRequired,
    rpa.PostHistoryTypeId,
    rpa.HistoryDate,
    rpa.Comment as HistoryComment,
    case when rpa.PostHistoryTypeId in (10, 12) then 'Closed or Deleted'
         when rpa.PostHistoryTypeId in (11, 13) then 'Reopened or Undeleted'
         else 'Other'
    end as PostStatus,
    count(*) over (partition by rua.UserId) as TotalPostsByUser,
    dense_rank() over (order by rua.Reputation desc) as ReputationRanking
from RecursiveUserActivity rua
left join UserBadgeStats ubs on ubs.UserId = rua.UserId
left join UserVoteSummary uvs on uvs.UserId = rua.UserId
left join QuestionAnswerRatio qar on qar.OwnerUserId = rua.UserId
left join PostLinkAgg pla on pla.PostId = rua.PostId
left join TopTags tt on tt.TagName = any(regexp_split_to_array(substring(rua.Tags from 2 for (length(rua.Tags) - 2)), '><'))
left join RecentPostActivity rpa on rpa.PostId = rua.PostId and rpa.HistoryRankDesc = 1
where rua.PostRank <= 5
  and (coalesce(ubs.GoldBadges,0) > 0 or coalesce(uvs.UpVotesGiven,0) > 100)
  and (rua.PostScore > 10 or rua.ViewCount > 1000)
group by
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.DistinctBadges,
    uvs.UpVotesGiven,
    uvs.DownVotesGiven,
    uvs.DistinctPostsVoted,
    uvs.TotalBountyGiven,
    qar.QuestionCount,
    qar.AnswerCount,
    qar.AnswerQuestionRatio,
    rua.PostId,
    rua.PostTypeId,
    rua.PostScore,
    rua.ViewCount,
    rua.Title,
    rua.Tags,
    pla.DuplicateCount,
    pla.LinkedCount,
    tt.TagName,
    tt.Count,
    tt.IsModeratorOnly,
    tt.IsRequired,
    rpa.PostHistoryTypeId,
    rpa.HistoryDate,
    rpa.Comment,
    rpa.HistoryRankDesc,
    rua.PostRank,
    rua.CreationDate,
    rua.PostCreationDate,
    rua.LastAccessDate
order by rua.Reputation desc, rua.PostScore desc
limit 100;