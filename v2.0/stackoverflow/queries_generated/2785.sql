-- {"query": "2785.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1717} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 100 and p.CreationDate is not null

    union all

    select 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.CreationDate,
        ph.PostId,
        pt.Id as PostTypeId,
        null as PostScore,
        null as ViewCount,
        ph.CreationDate as PostCreationDate,
        r.RecentPostRank + 1
    from RecursiveUserActivity r
    join PostHistory ph on ph.UserId = r.UserId and ph.PostId = r.PostId
    join PostTypes pt on pt.Id = ph.PostHistoryTypeId
    where r.RecentPostRank < 5
),
RecentHighActivityUsers as (
    select distinct UserId, DisplayName, Reputation, CreationDate
    from RecursiveUserActivity
    where RecentPostRank <= 5
),
QuestionAnswerDetails as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        max(case when a.Id = q.AcceptedAnswerId then a.Score else null end) as AcceptedAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.CreationDate >= current_date - interval '1 year'
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId
),
TagStats as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(q.AnswerCount, 0) as QuestionAnswers,
        coalesce(q.MaxAnswerScore, 0) as MaxAnswerScore
    from Tags t
    left join (
        select 
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
            count(p.Id) as AnswerCount,
            max(coalesce((
                select max(a.Score)
                from Posts a 
                where a.ParentId = p.Id and a.PostTypeId = 2
            ), 0)) as MaxAnswerScore
        from Posts p
        where p.PostTypeId = 1
        group by Tag
    ) q on q.Tag = t.TagName
),
UserBadgesWithRanks as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.TagBased,
        b.Date,
        rank() over (partition by b.UserId order by b.Class, b.Date) as BadgeRank
    from Badges b
),
TopUsersByBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        sum(p.Score) as TotalPostScore,
        max(p.Score) as MaxPostScore
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
    having count(distinct case when b.Class = 1 then b.Id end) >= 5
),
AggregatedVotes as (
    select 
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
DetailedPostAnalysis as (
    select 
        p.Id,
        p.Title,
        p.PostTypeId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount,
        av.UpVotes,
        av.DownVotes,
        av.Favorites,
        av.CloseVotes,
        case 
            when p.AcceptedAnswerId is not null then 'Accepted Answer Exists' 
            else 'No Accepted Answer' 
        end as AcceptedAnswerStatus,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc nulls last) as OwnerPostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join AggregatedVotes av on av.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
PostsWithCommentsCount as (
    select 
        p.Id as PostId,
        count(c.Id) as CommentCount
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
FinalSelection as (
    select 
        dpa.Id as PostId,
        dpa.Title,
        dpa.PostTypeId,
        dpa.OwnerName,
        dpa.Score,
        dpa.ViewCount,
        dpa.UpVotes,
        dpa.DownVotes,
        dpa.Favorites,
        dpa.CloseVotes,
        dpa.AcceptedAnswerStatus,
        dpa.OwnerPostRank,
        coalesce(pwc.CommentCount, 0) as CommentCount,
        concat_ws(' | ', 
            concat('Score: ', dpa.Score),
            concat('Views: ', dpa.ViewCount),
            concat('UpVotes: ', dpa.UpVotes),
            concat('DownVotes: ', dpa.DownVotes),
            concat('Comments: ', coalesce(pwc.CommentCount, 0))
        ) as PostSummary
    from DetailedPostAnalysis dpa
    left join PostsWithCommentsCount pwc on pwc.PostId = dpa.Id 
    where dpa.OwnerPostRank <= 3
)
select 
    fu.UserId,
    fu.DisplayName,
    fu.GoldBadges,
    fu.SilverBadges,
    fu.BronzeBadges,
    fu.TotalPostScore,
    fu.MaxPostScore,
    qad.QuestionId,
    qad.Title as QuestionTitle,
    qad.AnswerCount,
    qad.MaxAnswerScore,
    qad.AcceptedAnswerScore,
    ts.TagName,
    ts.Count as TagCount,
    ts.QuestionAnswers,
    ts.MaxAnswerScore as TagMaxAnswerScore,
    fs.PostId,
    fs.Title as PostTitle,
    fs.PostTypeId,
    fs.OwnerName,
    fs.Score as PostScore,
    fs.ViewCount as PostViews,
    fs.UpVotes,
    fs.DownVotes,
    fs.Favorites,
    fs.CloseVotes,
    fs.AcceptedAnswerStatus,
    fs.CommentCount,
    fs.PostSummary
from TopUsersByBadges fu
left join QuestionAnswerDetails qad on qad.QuestionOwner = fu.UserId
left join TagStats ts on ts.Count > 1000
left join FinalSelection fs on fs.OwnerName = fu.DisplayName
where fu.TotalPostScore > 1000
order by fu.GoldBadges desc, fu.TotalPostScore desc, qad.AnswerCount desc
limit 100;