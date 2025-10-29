-- {"query": "2853.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1719} 
with RecursiveAnswerCTE as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        1 as Level
    from Posts p
    where p.PostTypeId = 2
    union all
    select
        p.Id as AnswerId,
        cte.QuestionId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        cte.Level + 1
    from Posts p
    inner join RecursiveAnswerCTE cte on p.ParentId = cte.AnswerId and p.PostTypeId = 2
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Class) as Rank
    from Badges b
    group by b.UserId, b.Class
),
QuestionVoteSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
QuestionCommentCounts as (
    select 
        c.PostId,
        count(distinct c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on ph.Comment = cast(crt.Id as varchar)
    where pht.Name = 'Post Closed'
),
MostActiveUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as NumPosts,
        count(distinct b.Id) as NumBadges,
        max(p.CreationDate) as LastPostDate,
        round(avg(p.Score)::numeric, 2) as AvgPostScore,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(distinct p.Id) > 10
),
UserRankedBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Class, b.Date desc) as BadgeRank
    from Users u
    join Badges b on b.UserId = u.Id
),
DuplicateLinkedPosts as (
    select distinct
        pl.PostId,
        pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
QuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(qas.AnswerCount,0) as AnswerCount,
        coalesce(qvs.UpVotes,0) as UpVotes,
        coalesce(qvs.DownVotes,0) as DownVotes,
        coalesce(qvs.Favorites,0) as Favorites,
        q.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        qc.CloseReason,
        qc.CloseDate,
        concat_ws(' | ',
            left(q.Title, 50),
            coalesce(u.Location,'Unknown Location'),
            to_char(q.CreationDate, 'YYYY-MM-DD'),
            case when qc.CloseReason is not null then 'Closed: ' || qc.CloseReason else 'Open' end
        ) as SummaryString
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts where PostTypeId = 2
        group by ParentId
    ) qas on qas.ParentId = q.Id
    left join QuestionVoteSummary qvs on qvs.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join QuestionCloseReasons qc on qc.PostId = q.Id
    where q.PostTypeId = 1 and q.Score > 5
),
RankedAnswers as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
UserAnswerRanks as (
    select
        r.AnswerId,
        r.QuestionId,
        r.AnswererId,
        r.AnswerRank,
        u.DisplayName as AnswererName,
        u.Reputation as AnswererReputation
    from RankedAnswers r
    join Users u on u.Id = r.AnswererId
)
select
    q.QuestionId,
    q.Title,
    q.OwnerDisplayName,
    q.Location,
    q.CreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.UpVotes,
    q.DownVotes,
    q.Favorites,
    q.HasAcceptedAnswer,
    q.CloseReason,
    q.CloseDate,
    q.SummaryString,
    ua.AnswerId,
    ua.AnswerRank,
    ua.AnswerScore,
    ua.AnswerCreationDate,
    ua.AnswererName,
    ua.AnswererReputation,
    (select count(1) from Badges b where b.UserId = q.OwnerUserId and b.Class = 1) as OwnerGoldBadges,
    (select count(distinct c.Id) from Comments c where c.PostId = q.QuestionId and c.Score > 0) as PositiveCommentCount,
    case 
      when q.CloseReason is not null and q.CloseDate >= current_date - interval '30 days' then true 
      else false 
    end as RecentlyClosed,
    json_agg(distinct jsonb_build_object('Id', ph.Id, 'Type', pht.Name, 'UserId', ph.UserId, 'Date', ph.CreationDate))
        filter (where ph.PostId = q.QuestionId) as PostHistoryEntries
from QuestionsWithAnswers q
left join UserAnswerRanks ua on ua.QuestionId = q.QuestionId and ua.AnswerRank <= 3
left join PostHistory ph on ph.PostId = q.QuestionId
left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
group by 
    q.QuestionId, q.Title, q.OwnerDisplayName, q.Location, q.CreationDate, q.QuestionScore, q.ViewCount, q.AnswerCount, q.UpVotes, q.DownVotes, q.Favorites, q.HasAcceptedAnswer, q.CloseReason, q.CloseDate, q.SummaryString,
    ua.AnswerId, ua.AnswerRank, ua.AnswerScore, ua.AnswerCreationDate, ua.AnswererName, ua.AnswererReputation
having (q.UpVotes - q.DownVotes) > 10
order by q.ViewCount desc, q.CreationDate desc
limit 50;