with recursive RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        cast(array[t.TagName] as text[]) as TagPath,
        1 as Level
    from Tags t
    where not exists (
        select 1 
        from PostLinks pl 
        join Posts p on p.Id = pl.PostId 
        where pl.RelatedPostId = t.ExcerptPostId
    )
    union all
    select 
        t.Id,
        t.TagName,
        t.Count,
        rth.TagPath || t.TagName,
        rth.Level + 1
    from Tags t
    join PostLinks pl on pl.RelatedPostId = t.ExcerptPostId
    join RecursiveTagHierarchy rth on rth.Id = pl.PostId
    where t.Id <> pl.PostId
),
TopUsersWithBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 10000
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionsWithAnswersCTE as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate as QuestionCreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by p.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
),
FilteredAnswers as (
    select * from QuestionsWithAnswersCTE where AnswerRank <= 3
),
AnswerVotesRanked as (
    select
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        row_number() over (partition by v.PostId, v.VoteTypeId order by v.CreationDate desc) as VoteRankDesc
    from Votes v
),
RecentUpVotes as (
    select 
        avr.PostId,
        count(*) as RecentUpVotesCount
    from AnswerVotesRanked avr
    where avr.VoteTypeId = 2 and avr.VoteRankDesc <= 5
    group by avr.PostId
),
UserCommentActivity as (
    select
        c.UserId,
        count(c.Id) as TotalComments,
        count(distinct c.PostId) as PostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(ua.TotalComments,0) as TotalComments,
        coalesce(ua.PostsCommented,0) as PostsCommented,
        coalesce(ua.LastCommentDate, timestamp '1970-01-01 00:00:00') as LastCommentDate,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        case
            when (u.UpVotes + u.DownVotes) = 0 then null
            else round((cast(u.UpVotes as numeric) / NULLIF((u.UpVotes + u.DownVotes),0)), 2)
        end as UpVoteRatio
    from Users u
    left join UserCommentActivity ua on ua.UserId = u.Id
    group by u.Id, u.DisplayName, ua.TotalComments, ua.PostsCommented, ua.LastCommentDate, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
QuestionsClosedRecently as (
    select
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(coalesce(NULLIF(ph.Comment,''),'0') as smallint)
    where ph.PostHistoryTypeId = 10 and ph.CreationDate > (timestamp '2024-10-01 12:34:56') - interval '60 days'
),
UnionedBadgesGoldSilver as (
    select UserId, Name, Class from Badges where Class in (1, 2)
    union
    select UserId, Name || ' (Special)' as Name, Class from Badges where coalesce(TagBased, false) = true and Class in (1, 2)
)
select 
    q.QuestionId,
    q.Title,
    q.QuestionCreationDate,
    q.ViewCount,
    q.Tags,
    array_to_string(string_to_array(coalesce(q.Tags,''), '><'), ', ') as TagList,
    q.QuestionScore,
    q.AnswerId,
    q.AnswerScore,
    q.AnswerCreationDate,
    coalesce(ruv.RecentUpVotesCount, 0) as RecentTopAnswerUpVotes,
    tu.DisplayName as QuestionOwnerName,
    tu.Reputation as QuestionOwnerReputation,
    uas.TotalComments as QuestionOwnerTotalComments,
    uas.PostsCommented as QuestionOwnerPostsCommented,
    uas.UpVoteRatio as QuestionOwnerUpVoteRatio,
    qc.ClosedDate,
    qc.CloseReason,
    goldsilverbadges.UserId as BadgeUserId,
    goldsilverbadges.Name as BadgeName,
    goldsilverbadges.Class as BadgeClass,
    dense_rank() over (partition by q.QuestionId order by q.AnswerScore desc) as AnswerScoreRank,
    row_number() over (partition by tu.UserId order by q.QuestionCreationDate desc) as QuestionRecencyRank,
    case 
       when q.ViewCount > 10000 then 'High Traffic'
       when q.ViewCount > 1000 then 'Moderate Traffic'
       else 'Low Traffic'
    end as TrafficCategory
from FilteredAnswers q
left join RecentUpVotes ruv on ruv.PostId = q.AnswerId
left join TopUsersWithBadges tu on tu.UserId = q.OwnerUserId
left join UserActivitySummary uas on uas.UserId = q.OwnerUserId
left join QuestionsClosedRecently qc on qc.PostId = q.QuestionId
left join UnionedBadgesGoldSilver goldsilverbadges on goldsilverbadges.UserId = q.OwnerUserId
where q.QuestionCreationDate > (timestamp '2024-10-01 12:34:56') - interval '180 days'
  and (q.AnswerScore > (
    select avg(a2.Score)*1.1 
    from Posts a2 
    where a2.ParentId = q.QuestionId and a2.PostTypeId = 2
  ) or q.AnswerScore is null)
order by q.QuestionCreationDate desc, q.AnswerScore desc;