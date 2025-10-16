-- {"query": "784.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1446} 
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
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
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
            unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName,
            sum(p.AnswerCount) as AnswerCount,
            sum(p.ViewCount) as ViewCount
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) p on p.TagName = t.TagName
    where t.Count > 1000
),
PostLinkAgg as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
UserVoteSummary as (
    select
        u.Id as UserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        count(distinct v.PostId) as DistinctPostsVoted,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id
),
QuestionAnswerRatio as (
    select
        OwnerUserId,
        count(*) filter (where PostTypeId = 1) as QuestionCount,
        count(*) filter (where PostTypeId = 2) as AnswerCount,
        case when count(*) filter (where PostTypeId = 1) = 0 then null
             else count(*) filter (where PostTypeId = 2)::float / count(*) filter (where PostTypeId = 1)
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
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '180 days'
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
    substring(rua.Tags from 2 for char_length(rua.Tags)-2) as CleanTags,
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
left join TopTags tt on tt.TagName = any(string_to_array(substring(rua.Tags from 2 for char_length(rua.Tags)-2), '><'))
left join RecentPostActivity rpa on rpa.PostId = rua.PostId and rpa.HistoryRankDesc = 1
where rua.PostRank <= 5
  and (ubs.GoldBadges > 0 or uvs.UpVotesGiven > 100)
  and (rua.PostScore > 10 or rua.ViewCount > 1000)
order by rua.Reputation desc, rua.PostScore desc
limit 100;