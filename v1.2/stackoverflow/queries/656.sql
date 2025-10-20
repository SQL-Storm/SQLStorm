with recursive RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = true
    union all
    select 
        t2.Id,
        t2.TagName,
        t2.Count,
        rth.Path || array[t2.Id]
    from Tags t2
    join RecursiveTagHierarchy rth on true
    where t2.IsModeratorOnly = false 
      and t2.Count < rth.Count 
      and not t2.Id = any(rth.Path)
      and array_length(rth.Path,1) < 3
),
UserBadgeCounts as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostScoresRanked as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2) and p.OwnerUserId is not null
),
PostWithVotes as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        p.CreationDate
    from Posts p
    left join (
        select 
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId in (1,2)
),
QuestionsWithAcceptedAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerUserId,
        u.DisplayName as QuestionOwnerName,
        u.Reputation as QuestionOwnerReputation
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select 
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.Comment, crt.Name
),
TopUsersByBadgeRatio as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        case when ubc.BronzeBadges > 0 then (cast(ubc.GoldBadges as double precision) / ubc.BronzeBadges) else null end as GoldToBronzeRatio
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    where u.Reputation > 1000
    order by GoldToBronzeRatio desc nulls last
    limit 50
),
QuestionsWithDuplicateLinks as (
    select distinct
        q.Id as QuestionId,
        q.Title,
        pl.RelatedPostId as DuplicateOfPostId,
        dup.Title as DuplicateOfPostTitle
    from Posts q
    join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3 -- Duplicate
    join Posts dup on dup.Id = pl.RelatedPostId
    where q.PostTypeId = 1
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct ph.Id) as TotalPostEdits,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id and ph.PostHistoryTypeId in (4,5,6) -- Edit Title/Body/Tags
    group by u.Id, u.DisplayName
)
select 
    tth.TagName,
    tth.Count as TagCount,
    coalesce(qac.QuestionCount,0) as QuestionsCount,
    coalesce(ansc.AnswerCount,0) as AnswersCount,
    crc.CloseReasonName,
    crc.CloseCount,
    tur.DisplayName as TopUserDisplayName,
    tur.Reputation as TopUserReputation,
    tur.GoldBadges,
    tur.SilverBadges,
    tur.BronzeBadges,
    tur.GoldToBronzeRatio,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalPostEdits,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.LastEditDate
from RecursiveTagHierarchy tth
left join (
    select 
        tag as TagName,
        count(*) as QuestionCount
    from (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
        from Posts p
        where p.PostTypeId = 1
    ) s
    group by tag
) qac on qac.TagName = tth.TagName
left join (
    select 
        tag as TagName,
        count(*) as AnswerCount
    from (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
        from Posts p
        where p.PostTypeId = 2
    ) s
    group by tag
) ansc on ansc.TagName = tth.TagName
left join CloseReasonCounts crc on crc.CloseReasonName like '%' || tth.TagName || '%'
left join TopUsersByBadgeRatio tur on tur.Id = (
    select p2.OwnerUserId from Posts p2 
    where p2.PostTypeId = 1 and p2.Tags like '%' || tth.TagName || '%'
    order by p2.Score desc limit 1
)
left join UserActivitySummary uas on uas.UserId = tur.Id
where tth.Count > 100
group by
    tth.TagName,
    tth.Count,
    qac.QuestionCount,
    ansc.AnswerCount,
    crc.CloseReasonName,
    crc.CloseCount,
    tur.DisplayName,
    tur.Reputation,
    tur.GoldBadges,
    tur.SilverBadges,
    tur.BronzeBadges,
    tur.GoldToBronzeRatio,
    uas.TotalPosts,
    uas.TotalComments,
    uas.TotalPostEdits,
    uas.LastPostDate,
    uas.LastCommentDate,
    uas.LastEditDate
order by tth.Count desc, crc.CloseCount desc
limit 100;